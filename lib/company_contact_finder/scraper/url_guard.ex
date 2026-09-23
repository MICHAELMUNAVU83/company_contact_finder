defmodule CompanyContactFinder.Scraper.UrlGuard do
  @moduledoc """
  URL validation for anything the crawler fetches.

  Every URL (including each redirect hop) must be http(s) and must not point
  at localhost or a private, loopback or link-local address. This stops a
  search result or a user-supplied website from making the server request
  internal services (SSRF).
  """

  import Bitwise

  @doc """
  Parses a URL (adding `https://` if no scheme is given) and returns its root,
  e.g. `"https://example.com"`.
  """
  @spec normalize_root(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def normalize_root(url) when is_binary(url) do
    with {:ok, uri} <- parse(url) do
      port = if uri.port in [nil, URI.default_port(uri.scheme)], do: "", else: ":#{uri.port}"
      {:ok, "#{uri.scheme}://#{uri.host}#{port}"}
    end
  end

  def normalize_root(_), do: {:error, :invalid_url}

  @doc """
  Parses and validates a URL. Returns the `URI` if it is safe to fetch.
  """
  @spec parse(String.t()) :: {:ok, URI.t()} | {:error, atom()}
  def parse(url) when is_binary(url) do
    url = String.trim(url)
    url = if url =~ ~r/^[a-z][a-z0-9+.-]*:\/\//i, do: url, else: "https://" <> url

    with {:ok, uri} <- URI.new(url),
         :ok <- check_scheme(uri),
         :ok <- check_host(uri.host) do
      {:ok, %{uri | host: String.downcase(uri.host), scheme: String.downcase(uri.scheme)}}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _part} -> {:error, :invalid_url}
    end
  end

  def parse(_), do: {:error, :invalid_url}

  @doc "True if both hosts are the same site, ignoring a leading `www.`."
  @spec same_site?(String.t() | nil, String.t() | nil) :: boolean()
  def same_site?(a, b) when is_binary(a) and is_binary(b), do: bare(a) == bare(b)
  def same_site?(_, _), do: false

  defp bare(host), do: host |> String.downcase() |> String.replace_prefix("www.", "")

  defp check_scheme(%URI{scheme: scheme}) when is_binary(scheme) do
    if String.downcase(scheme) in ["http", "https"], do: :ok, else: {:error, :unsupported_scheme}
  end

  defp check_scheme(_), do: {:error, :unsupported_scheme}

  defp check_host(host) when host in [nil, ""], do: {:error, :invalid_url}

  defp check_host(host) do
    host = String.downcase(host)

    cond do
      host == "localhost" or String.ends_with?(host, ".localhost") ->
        {:error, :private_host}

      String.ends_with?(host, ".local") or String.ends_with?(host, ".internal") ->
        {:error, :private_host}

      not String.contains?(host, ".") and ip_literal(host) == nil ->
        {:error, :invalid_url}

      true ->
        check_ips(host)
    end
  end

  defp check_ips(host) do
    ips =
      case ip_literal(host) do
        nil -> if resolve_dns?(), do: resolve(host), else: []
        ip -> [ip]
      end

    cond do
      ips == :nxdomain -> {:error, :unresolvable_host}
      Enum.any?(ips, &private_ip?/1) -> {:error, :private_host}
      true -> :ok
    end
  end

  defp ip_literal(host) do
    host = host |> String.trim_leading("[") |> String.trim_trailing("]")

    case :inet.parse_strict_address(String.to_charlist(host)) do
      {:ok, ip} -> ip
      {:error, _} -> nil
    end
  end

  defp resolve(host) do
    charlist = String.to_charlist(host)

    v4 =
      case :inet.getaddrs(charlist, :inet),
        do: (
          {:ok, ips} -> ips
          _ -> []
        )

    v6 =
      case :inet.getaddrs(charlist, :inet6),
        do: (
          {:ok, ips} -> ips
          _ -> []
        )

    case v4 ++ v6 do
      [] -> :nxdomain
      ips -> ips
    end
  end

  defp resolve_dns? do
    Application.get_env(:company_contact_finder, :scraper, [])[:resolve_dns_guard] != false
  end

  @doc false
  def private_ip?({a, b, _, _}) do
    a == 0 or a == 10 or a == 127 or
      (a == 100 and b >= 64 and b <= 127) or
      (a == 169 and b == 254) or
      (a == 172 and b >= 16 and b <= 31) or
      (a == 192 and b == 168) or
      (a == 198 and b in [18, 19]) or
      a >= 224
  end

  def private_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  def private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  # IPv4-mapped IPv6 (::ffff:a.b.c.d)
  def private_ip?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: private_ip?({hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF})

  def private_ip?({first, _, _, _, _, _, _, _}) do
    # fc00::/7 unique local, fe80::/10 link local, ff00::/8 multicast
    (first &&& 0xFE00) == 0xFC00 or (first &&& 0xFFC0) == 0xFE80 or (first &&& 0xFF00) == 0xFF00
  end
end
