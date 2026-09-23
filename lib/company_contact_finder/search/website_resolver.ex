defmodule CompanyContactFinder.Search.WebsiteResolver do
  @moduledoc """
  Picks a company's official website from Serper search results.

  Order of preference:

    1. `knowledgeGraph.website`, when Google shows one.
    2. The best-scoring organic result that is not a directory or social site.
       Earlier results score higher, domains that contain the company
       name get a bonus, and so do domains under the search country's TLD
       (e.g. `.co.ke`).

  If neither exists, `resolve_listing/2` picks the company's page on a
  business directory (e.g. Yellow Pages Kenya) as a fallback source.
  """

  alias CompanyContactFinder.Scraper.UrlGuard
  alias CompanyContactFinder.Search

  # Directories whose listing pages hold a company's contact details.
  @listing_domains ~w(
    yellowpageskenya.com yellow.co.ke businesslist.co.ke kenyabizdirectory.com
    kenyaplex.com cybo.com yelp.com yellowpages.com opencorporates.com
  )

  @blocked_domains @listing_domains ++
                     ~w(
    linkedin.com facebook.com instagram.com x.com twitter.com tiktok.com
    youtube.com pinterest.com reddit.com medium.com wikipedia.org
    wikidata.org crunchbase.com bloomberg.com reuters.com forbes.com
    glassdoor.com indeed.com zoominfo.com dnb.com
    apollo.io rocketreach.co signalhire.com
    craft.co owler.com pitchbook.com tracxn.com cbinsights.com
    trustpilot.com mapquest.com google.com goo.gl
    apple.com amazon.com play.google.com apps.apple.com
  )

  @legal_suffixes ~w(
    ltd limited inc incorporated llc llp plc co corp corporation company
    group holdings gmbh sa sarl bv pty pvt private the and kenya africa
  )

  @type candidate :: %{String.t() => term()}

  @doc """
  Returns `{:ok, url, candidates}` where `url` is the chosen root URL and
  `candidates` is every eligible result with its score, best first.
  """
  @spec resolve(String.t(), map()) :: {:ok, String.t(), [candidate()]} | {:error, :no_website}
  def resolve(company_name, serper_body) when is_map(serper_body) do
    tokens = name_tokens(company_name)

    candidates =
      serper_body
      |> raw_candidates()
      |> Enum.flat_map(&to_candidate(&1, tokens))
      |> Enum.uniq_by(& &1["host"])
      |> Enum.sort_by(& &1["score"], :desc)

    case candidates do
      [%{"url" => url} | _] -> {:ok, url, candidates}
      [] -> {:error, :no_website}
    end
  end

  @doc """
  Returns `{:ok, url}` for the best directory listing page whose title names
  the company, or `{:error, :no_website}`.
  """
  @spec resolve_listing(String.t(), map()) :: {:ok, String.t()} | {:error, :no_website}
  def resolve_listing(company_name, serper_body) when is_map(serper_body) do
    tokens = name_tokens(company_name)

    serper_body
    |> raw_candidates()
    |> Enum.filter(&(&1.source == "organic"))
    |> Enum.find_value({:error, :no_website}, fn %{url: url, title: title} ->
      with {:ok, uri} <- UrlGuard.parse(url),
           true <- listing_host?(uri.host),
           false <- uri.path in [nil, "", "/"],
           true <- title_names_company?(title, tokens) do
        {:ok, URI.to_string(%{uri | fragment: nil})}
      else
        _ -> nil
      end
    end)
  end

  @doc "True if the host belongs to a directory, social or news site."
  @spec blocked_host?(String.t()) :: boolean()
  def blocked_host?(host), do: host_in?(host, @blocked_domains)

  @doc "True if the host is a business directory with company listing pages."
  @spec listing_host?(String.t()) :: boolean()
  def listing_host?(host), do: host_in?(host, @listing_domains)

  defp host_in?(host, domains) do
    host = String.downcase(host)
    Enum.any?(domains, &(host == &1 or String.ends_with?(host, "." <> &1)))
  end

  # Most of the company's name words must appear in the title. Matching by
  # prefix lets "Chemicals" match "Chemical".
  defp title_names_company?(_title, []), do: false

  defp title_names_company?(title, tokens) when is_binary(title) do
    title_tokens = name_tokens(title)

    matches =
      Enum.count(tokens, fn token ->
        stem = String.replace_suffix(token, "s", "")
        Enum.any?(title_tokens, &String.starts_with?(&1, stem))
      end)

    matches >= max(ceil(length(tokens) * 2 / 3), 1)
  end

  defp title_names_company?(_title, _tokens), do: false

  defp raw_candidates(body) do
    knowledge_graph =
      case get_in(body, ["knowledgeGraph", "website"]) do
        url when is_binary(url) ->
          [
            %{
              url: url,
              title: get_in(body, ["knowledgeGraph", "title"]),
              source: "knowledge_graph",
              position: 0
            }
          ]

        _ ->
          []
      end

    organic =
      body
      |> Map.get("organic", [])
      |> List.wrap()
      |> Enum.with_index(1)
      |> Enum.flat_map(fn
        {%{"link" => url} = result, index} when is_binary(url) ->
          [
            %{
              url: url,
              title: result["title"],
              source: "organic",
              position: result["position"] || index
            }
          ]

        _ ->
          []
      end)

    knowledge_graph ++ organic
  end

  defp to_candidate(%{url: url} = raw, tokens) do
    with {:ok, root} <- UrlGuard.normalize_root(url),
         host = URI.parse(root).host,
         false <- blocked_host?(host) do
      [
        %{
          "url" => root,
          "host" => host,
          "title" => raw.title,
          "source" => raw.source,
          "position" => raw.position,
          "score" => score(raw, host, tokens)
        }
      ]
    else
      _ -> []
    end
  end

  defp score(%{source: "knowledge_graph"}, _host, _tokens), do: 100

  defp score(%{position: position}, host, tokens) do
    base = max(60 - position * 4, 0)
    base + name_bonus(host, tokens) + country_bonus(host)
  end

  defp country_bonus(host) do
    case Search.country_code() do
      code when is_binary(code) -> if String.ends_with?(host, "." <> code), do: 10, else: 0
      _ -> 0
    end
  end

  defp name_bonus(_host, []), do: 0

  defp name_bonus(host, tokens) do
    label = host |> String.replace_prefix("www.", "") |> String.split(".") |> hd()
    joined = Enum.join(tokens)
    initials = tokens |> Enum.map(&String.first/1) |> Enum.join()

    cond do
      label == joined -> 40
      String.contains?(label, joined) -> 30
      length(tokens) > 1 and label == initials -> 20
      Enum.any?(tokens, &(String.length(&1) >= 4 and String.contains?(label, &1))) -> 15
      true -> 0
    end
  end

  @doc false
  def name_tokens(company_name) do
    company_name
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[^a-z0-9\s]/u, "")
    |> String.split()
    |> Enum.reject(&(&1 in @legal_suffixes))
  end
end
