defmodule CompanyContactFinder.Leads.Discovery do
  @moduledoc """
  Suggests companies for a lead bucket. Searches Google for rankings, lists
  and directories (e.g. "top healthcare manufacturing companies in Kenya"),
  reads the most relevant pages and asks
  `CompanyContactFinder.AI.CompanyFinder` which companies they name.

  Suggestions aren't saved; the user picks which to add to the bucket.
  """

  alias CompanyContactFinder.AI.CompanyFinder
  alias CompanyContactFinder.Leads.Bucket
  alias CompanyContactFinder.Scraper.{Crawler, Extractor, UrlGuard}
  alias CompanyContactFinder.Search
  alias CompanyContactFinder.Search.Serper

  @max_queries 4
  @max_pages 8

  # Sites that need a login or aren't text, so their pages can't be read.
  @unreadable_domains ~w(
    linkedin.com facebook.com instagram.com x.com twitter.com tiktok.com
    youtube.com pinterest.com
  )

  @doc """
  Returns `{:ok, %{queries: [...], suggestions: [...]}}`. Companies whose
  names are in `:exclude` (case-insensitive) are left out.
  """
  def discover(%Bucket{} = bucket, opts \\ []) do
    queries = queries(bucket)
    exclude = opts |> Keyword.get(:exclude, []) |> MapSet.new(&String.downcase/1)

    with {:ok, results} <- search_all(queries),
         sources when sources != [] <- read_sources(results),
         {:ok, suggestions} <- CompanyFinder.find(bucket, sources) do
      suggestions = Enum.reject(suggestions, &(String.downcase(&1.name) in exclude))
      {:ok, %{queries: queries, suggestions: suggestions}}
    else
      [] -> {:ok, %{queries: queries, suggestions: []}}
      error -> error
    end
  end

  @doc "Search queries for the bucket's industries and first location."
  def queries(%Bucket{} = bucket) do
    location = location(bucket)

    topics =
      case bucket.industries do
        [] -> [bucket.target_description |> String.slice(0, 80) |> String.trim()]
        industries -> industries
      end

    topics
    |> Enum.flat_map(fn topic ->
      ["top #{topic} companies in #{location}", "list of #{topic} companies in #{location}"]
    end)
    |> Enum.map(&String.trim/1)
    |> Enum.uniq()
    |> Enum.take(@max_queries)
  end

  defp location(bucket) do
    country = Search.country_name()

    case bucket.locations do
      [first | _] ->
        if country && not String.contains?(String.downcase(first), String.downcase(country)),
          do: "#{first} #{country}",
          else: first

      [] ->
        country || ""
    end
  end

  # Organic results for every query, best-ranked first. Fails only if every search fails.
  defp search_all(queries) do
    responses = Enum.map(queries, &Serper.search/1)

    case Enum.filter(responses, &match?({:ok, _}, &1)) do
      [] ->
        List.first(responses, {:error, :no_queries})

      ok ->
        results =
          ok
          |> Enum.map(fn {:ok, body} -> List.wrap(body["organic"]) end)
          |> interleave()
          |> Enum.filter(&(is_binary(&1["link"]) and readable?(&1["link"])))
          |> Enum.uniq_by(& &1["link"])

        {:ok, results}
    end
  end

  # Takes the first result of every query, then the second, and so on.
  defp interleave(lists) do
    lists
    |> Enum.map(&Enum.with_index/1)
    |> List.flatten()
    |> Enum.sort_by(fn {_result, index} -> index end)
    |> Enum.map(fn {result, _index} -> result end)
  end

  defp readable?(url) do
    case UrlGuard.parse(url) do
      {:ok, %URI{host: host}} ->
        host = String.downcase(host)
        not Enum.any?(@unreadable_domains, &(host == &1 or String.ends_with?(host, "." <> &1)))

      _ ->
        false
    end
  end

  # Each result's page text, falling back to its search snippet if the page can't be read.
  defp read_sources(results) do
    results
    |> Enum.take(@max_pages)
    |> Task.async_stream(&read_source/1,
      max_concurrency: 4,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Enum.zip(Enum.take(results, @max_pages))
    |> Enum.flat_map(fn
      {{:ok, source}, _result} -> [source]
      {{:exit, _}, result} -> [snippet_source(result)]
    end)
    |> Enum.reject(&(&1.text == ""))
  end

  defp read_source(result) do
    source = snippet_source(result)

    case Crawler.crawl_page(result["link"]) do
      {:ok, [page | _]} ->
        %{text: text} = Extractor.extract(page.html, page.url)
        %{source | text: String.trim("#{source.text}\n#{text}")}

      {:error, _} ->
        source
    end
  end

  defp snippet_source(result) do
    %{
      url: result["link"],
      title: result["title"] || result["link"],
      text: result["snippet"] || ""
    }
  end
end
