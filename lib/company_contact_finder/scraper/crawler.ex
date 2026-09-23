defmodule CompanyContactFinder.Scraper.Crawler do
  @moduledoc """
  Politely fetches a handful of pages from a company website: the homepage
  plus pages likely to hold contact details.

  Same site only, robots.txt respected, one request at a time with a delay,
  every URL (and redirect hop) checked by `CompanyContactFinder.Scraper.UrlGuard`.
  """
  require Logger

  alias CompanyContactFinder.Scraper.{Robots, UrlGuard}

  @common_paths ~w(/contact /contact-us /contacts /about /about-us /team /our-team /impressum /support)
  @link_keywords ~w(contact about team impressum support reach touch office location)
  @skip_extensions ~w(.pdf .jpg .jpeg .png .gif .svg .webp .zip .mp4 .mp3 .doc .docx .xls .xlsx .ppt .pptx)

  @type page :: %{url: String.t(), html: String.t()}

  @doc """
  Crawls the site at `root_url`. Returns the pages fetched, homepage first.
  Fails only if the homepage cannot be fetched.
  """
  @spec crawl(String.t(), keyword()) :: {:ok, [page()]} | {:error, term()}
  def crawl(root_url, opts \\ []) do
    config = Keyword.merge(Application.fetch_env!(:company_contact_finder, :scraper), opts)

    with {:ok, root} <- UrlGuard.parse(root_url),
         root = %{root | path: "/", query: nil, fragment: nil},
         robots = fetch_robots(root, config),
         {:ok, home} <- fetch_page(URI.to_string(root), config) do
      site_host = URI.parse(home.url).host

      extra_pages =
        home.html
        |> discover_links(home.url, site_host)
        |> Kernel.++(
          Enum.map(
            @common_paths,
            &URI.to_string(%{URI.parse(home.url) | path: &1, query: nil, fragment: nil})
          )
        )
        |> Enum.uniq_by(&canonical/1)
        |> Enum.reject(&(canonical(&1) == canonical(home.url)))
        |> Enum.filter(&Robots.allowed?(robots, URI.parse(&1).path))
        |> Enum.take(config[:max_pages] - 1)
        |> Enum.flat_map(fn url ->
          polite_delay(config)

          case fetch_page(url, config) do
            {:ok, page} ->
              if UrlGuard.same_site?(URI.parse(page.url).host, site_host), do: [page], else: []

            {:error, _} ->
              []
          end
        end)
        |> Enum.uniq_by(&canonical(&1.url))

      {:ok, [home | extra_pages]}
    end
  end

  @doc """
  Fetches a single page, e.g. a company's listing on a directory site. No
  other pages on that site are crawled. Returns the page in a list, like `crawl/2`.
  """
  @spec crawl_page(String.t(), keyword()) :: {:ok, [page()]} | {:error, term()}
  def crawl_page(url, opts \\ []) do
    config = Keyword.merge(Application.fetch_env!(:company_contact_finder, :scraper), opts)

    with {:ok, uri} <- UrlGuard.parse(url),
         robots = fetch_robots(%{uri | query: nil, fragment: nil}, config),
         true <- Robots.allowed?(robots, uri.path || "/") || {:error, :robots_disallowed},
         {:ok, page} <- fetch_page(URI.to_string(%{uri | fragment: nil}), config) do
      {:ok, [page]}
    end
  end

  @doc false
  def discover_links(html, base_url, site_host) do
    base = URI.parse(base_url)

    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("a[href]")
    |> Enum.flat_map(fn node ->
      href = node |> LazyHTML.attribute("href") |> List.first("")
      text = node |> LazyHTML.text() |> String.downcase()

      with false <- href =~ ~r/^(mailto|tel|javascript|data):/i,
           {:ok, uri} <- safe_merge(base, href),
           true <- uri.scheme in ["http", "https"],
           true <- UrlGuard.same_site?(uri.host, site_host),
           path = String.downcase(uri.path || "/"),
           false <- Enum.any?(@skip_extensions, &String.ends_with?(path, &1)),
           true <-
             Enum.any?(
               @link_keywords,
               &(String.contains?(path, &1) or String.contains?(text, &1))
             ) do
        [URI.to_string(%{uri | fragment: nil})]
      else
        _ -> []
      end
    end)
  end

  defp safe_merge(base, href) do
    {:ok, URI.merge(base, String.trim(href))}
  rescue
    _ -> :error
  end

  defp canonical(url) do
    uri = URI.parse(url)
    path = (uri.path || "/") |> String.trim_trailing("/")
    "#{String.replace_prefix(uri.host || "", "www.", "")}#{path}"
  end

  defp fetch_robots(root, config) do
    url = URI.to_string(%{root | path: "/robots.txt", query: nil})

    case request(url, config) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) -> Robots.parse(body)
      _ -> []
    end
  end

  defp fetch_page(url, config), do: fetch_page(url, config, config[:max_redirects])

  defp fetch_page(url, config, redirects_left) do
    with {:ok, _uri} <- UrlGuard.parse(url),
         {:ok, response} <- request(url, config) do
      case response do
        %Req.Response{status: status} when status in [301, 302, 303, 307, 308] ->
          follow_redirect(url, response, config, redirects_left)

        %Req.Response{status: 200, body: body} when is_binary(body) ->
          if html?(response),
            do: {:ok, %{url: url, html: truncate(body, config[:max_body_bytes])}},
            else: {:error, :not_html}

        %Req.Response{status: status} ->
          {:error, {:http_error, status}}
      end
    end
  end

  defp follow_redirect(_url, _response, _config, 0), do: {:error, :too_many_redirects}

  defp follow_redirect(url, response, config, redirects_left) do
    case Req.Response.get_header(response, "location") do
      [location | _] ->
        fetch_page(URI.to_string(URI.merge(url, location)), config, redirects_left - 1)

      [] ->
        {:error, :bad_redirect}
    end
  end

  defp request(url, config) do
    [
      url: url,
      redirect: false,
      decode_body: false,
      receive_timeout: config[:request_timeout],
      connect_options: [timeout: config[:request_timeout]],
      retry: :transient,
      max_retries: 1,
      headers: [
        {"user-agent", config[:user_agent]},
        {"accept", "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5"}
      ]
    ]
    |> Keyword.merge(config[:req_options] || [])
    |> Req.get()
    |> case do
      {:ok, response} ->
        {:ok, response}

      {:error, exception} ->
        Logger.debug("Crawl request to #{url} failed: #{Exception.message(exception)}")
        {:error, {:request_failed, Exception.message(exception)}}
    end
  end

  defp html?(response) do
    case Req.Response.get_header(response, "content-type") do
      [] -> true
      [type | _] -> String.contains?(type, "html")
    end
  end

  defp truncate(body, max) when is_integer(max) and byte_size(body) > max,
    do: binary_part(body, 0, max)

  defp truncate(body, _max), do: body

  defp polite_delay(config) do
    case config[:crawl_delay_ms] do
      ms when is_integer(ms) and ms > 0 -> Process.sleep(ms)
      _ -> :ok
    end
  end
end
