defmodule CompanyContactFinder.Leads.Pipeline do
  @moduledoc """
  Runs one lookup end to end (the brief is scored against the lookup's bucket):

      search (Serper) -> resolve website -> crawl -> extract contacts -> AI brief

  If the company has no website of its own, its page on a business directory
  is used instead, and only that page is fetched.

  Each step updates the lookup's status and broadcasts progress. The AI step
  is optional: if it fails, the lookup still finishes with its contacts and
  the brief is marked `:failed`.
  """
  require Logger

  alias CompanyContactFinder.AI.{CompanyAnalyst, OpenAI}
  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Lookup
  alias CompanyContactFinder.Repo
  alias CompanyContactFinder.Scraper.{Crawler, Extractor}
  alias CompanyContactFinder.Search
  alias CompanyContactFinder.Search.{Serper, WebsiteResolver}

  @max_scraped_chars 15_000

  @doc "Runs the full pipeline for the lookup with `lookup_id`."
  def run(lookup_id) do
    lookup = Repo.get!(Lookup, lookup_id)

    with {:ok, lookup} <- resolve_website(lookup),
         {:ok, lookup} <- crawl(lookup) do
      analyse(lookup.id)
    else
      {:error, reason} -> fail(lookup_id, reason)
    end
  rescue
    exception ->
      Logger.error(
        "Lookup #{lookup_id} crashed: " <> Exception.format(:error, exception, __STACKTRACE__)
      )

      fail(lookup_id, :unexpected_error)
  end

  @doc "Runs (or re-runs) only the AI brief step, then marks the lookup done."
  def analyse(lookup_id) do
    lookup = Lookup |> Repo.get!(lookup_id) |> Repo.preload(:bucket)
    {:ok, lookup} = Leads.update_progress(lookup, %{status: :analysing})
    contacts = Leads.list_contacts(lookup)

    cond do
      not OpenAI.configured?() ->
        Leads.save_brief(lookup, %{status: :failed, error: "OpenAI API key is not configured"})

      is_nil(lookup.scraped_text) ->
        Leads.save_brief(lookup, %{status: :failed, error: "No website text to analyse"})

      true ->
        Leads.save_brief(lookup, %{status: :pending, error: nil})

        case CompanyAnalyst.analyse(lookup, contacts, lookup.bucket) do
          {:ok, %{contacts_analysis: analysis} = attrs} ->
            {:ok, _brief} = Leads.save_brief(lookup, Map.delete(attrs, :contacts_analysis))
            Leads.apply_contact_analysis(lookup, analysis)

          {:error, reason} ->
            Logger.warning("Brief for lookup #{lookup_id} failed: #{inspect(reason)}")
            Leads.save_brief(lookup, %{status: :failed, error: describe(reason)})
        end
    end

    Leads.update_progress(lookup, %{status: :done, error: nil})
  rescue
    exception ->
      Logger.error(
        "Brief for lookup #{lookup_id} crashed: " <>
          Exception.format(:error, exception, __STACKTRACE__)
      )

      lookup = Repo.get!(Lookup, lookup_id)
      Leads.save_brief(lookup, %{status: :failed, error: "Unexpected error while analysing"})
      Leads.update_progress(lookup, %{status: :done})
  end

  defp resolve_website(%Lookup{website_overridden: true, website_url: url} = lookup)
       when is_binary(url),
       do: {:ok, lookup}

  defp resolve_website(lookup) do
    query = search_query(lookup.company_name)
    {:ok, lookup} = Leads.update_progress(lookup, %{status: :searching, query: query})

    with {:ok, body} <- Serper.search(query) do
      case WebsiteResolver.resolve(lookup.company_name, body) do
        {:ok, url, candidates} ->
          Leads.update_progress(lookup, %{
            website_url: url,
            source: :website,
            candidates: Enum.take(candidates, 8)
          })

        # No official site: fall back to the company's directory listing.
        {:error, :no_website} ->
          with {:ok, url} <- WebsiteResolver.resolve_listing(lookup.company_name, body) do
            Leads.update_progress(lookup, %{website_url: url, source: :listing, candidates: []})
          end
      end
    end
  end

  # Adds the country unless the company name already mentions it.
  defp search_query(company_name) do
    country = Search.country_name()

    if is_nil(country) or
         String.contains?(String.downcase(company_name), String.downcase(country)),
       do: "#{company_name} official website",
       else: "#{company_name} #{country} official website"
  end

  defp crawl(lookup) do
    {:ok, lookup} = Leads.update_progress(lookup, %{status: :crawling})
    listing? = lookup.source == :listing

    fetched =
      if listing?,
        do: Crawler.crawl_page(lookup.website_url),
        else: Crawler.crawl(lookup.website_url)

    with {:ok, pages} <- fetched do
      texts =
        Enum.map(pages, fn page ->
          %{contacts: contacts, text: text, title: title} =
            Extractor.extract(page.html, page.url, listing: listing?)

          Leads.add_contacts(lookup, contacts)
          "## #{title || page.url} (#{page.url})\n#{text}"
        end)

      Leads.update_progress(lookup, %{
        pages_crawled: length(pages),
        scraped_text: texts |> Enum.join("\n\n") |> String.slice(0, @max_scraped_chars)
      })
    end
  end

  defp fail(lookup_id, reason) do
    lookup = Repo.get!(Lookup, lookup_id)
    Leads.update_progress(lookup, %{status: :failed, error: describe(reason)})
  end

  @doc false
  def describe(:missing_serper_api_key), do: "Serper API key is not configured (SERPER_API_KEY)"
  def describe(:missing_openai_api_key), do: "OpenAI API key is not configured (OPENAI_API_KEY)"

  def describe(:no_website),
    do: "Couldn't find an official website or directory listing in the search results"

  def describe(:robots_disallowed), do: "The site's robots.txt doesn't allow fetching that page"
  def describe({:serper_http_error, 401}), do: "Serper rejected the API key"
  def describe({:serper_http_error, 403}), do: "Serper rejected the API key"
  def describe({:serper_http_error, status}), do: "Search failed (HTTP #{status})"
  def describe({:serper_request_failed, msg}), do: "Search request failed: #{msg}"
  def describe({:http_error, status}), do: "Website returned HTTP #{status}"
  def describe({:request_failed, msg}), do: "Couldn't reach the website: #{msg}"
  def describe(:not_html), do: "Website didn't return an HTML page"
  def describe(:too_many_redirects), do: "Website redirected too many times"
  def describe(:private_host), do: "Refusing to crawl a private or local address"
  def describe(:unresolvable_host), do: "Website domain doesn't resolve"
  def describe(:unsupported_scheme), do: "Only http(s) websites can be crawled"
  def describe(:invalid_url), do: "Website URL is invalid"
  def describe({:openai_http_error, 401}), do: "OpenAI rejected the API key"
  def describe({:openai_http_error, 429}), do: "OpenAI rate limit or quota exceeded"
  def describe({:openai_http_error, status}), do: "OpenAI request failed (HTTP #{status})"
  def describe({:openai_request_failed, msg}), do: "OpenAI request failed: #{msg}"
  def describe({:openai_refused, msg}), do: "OpenAI refused: #{msg}"
  def describe(:unexpected_error), do: "Unexpected error, check the server logs"
  def describe(other), do: "Failed: #{inspect(other)}"
end
