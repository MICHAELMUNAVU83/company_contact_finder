defmodule CompanyContactFinder.Scraper.Extractor do
  @moduledoc """
  Extracts public contact details (emails, phone numbers, social profiles)
  and readable text from a web page.
  """

  alias CompanyContactFinder.Scraper.UrlGuard

  @email_regex ~r/\b[a-z0-9][a-z0-9._%+-]{0,63}@(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}\b/i
  @phone_keyword_regex ~r/\b(?:phone|tel|telephone|call(?:\s+us)?|mobile|cell|whatsapp|fax|hotline)\s*(?:no\.?|number)?\s*[:.\-]?\s*(\+?\(?\d[\d\s().\-]{5,}\d)/i

  @asset_extensions ~w(.png .jpg .jpeg .gif .svg .webp .avif .css .js)
  @ignored_email_domains ~w(
    example.com example.org example.net domain.com yourdomain.com email.com
    sentry.io sentry-next.wixpress.com sentry.wixpress.com wixpress.com
    mysite.com company.com test.com
  )

  @social_hosts %{
    "linkedin.com" => "linkedin",
    "facebook.com" => "facebook",
    "x.com" => "x",
    "twitter.com" => "x",
    "instagram.com" => "instagram"
  }
  @social_skip ~r/(sharer|share|intent|dialog|login|plugins|hashtag|\/p\/|\/posts\/|\/status\/)/i

  @type contact :: %{type: :email | :phone | :social, value: String.t(), source_url: String.t()}

  @doc """
  Returns `%{contacts: [...], text: visible_text, title: page_title}`.

  Options:

    * `:listing` - the page is a company's listing on a directory site. The
      site's header, footer, nav and sidebars are dropped, as are emails on
      the directory's own domain and the directory's own social profiles.
  """
  @spec extract(String.t(), String.t(), keyword()) :: %{
          contacts: [contact()],
          text: String.t(),
          title: String.t() | nil
        }
  def extract(html, source_url, opts \\ []) do
    listing? = Keyword.get(opts, :listing, false)

    html = strip_non_content(html)
    title = page_title(html)
    html = if listing?, do: strip_site_chrome(html), else: html

    doc = html |> space_out_tags() |> LazyHTML.from_document()
    hrefs = doc |> LazyHTML.query("a[href]") |> LazyHTML.attribute("href")
    text = visible_text(doc)

    emails =
      (mailto_emails(hrefs) ++ text_emails(text)) |> Enum.filter(&valid_email?/1) |> Enum.uniq()

    phones = (tel_phones(hrefs) ++ text_phones(text)) |> Enum.uniq()
    socials = hrefs |> Enum.flat_map(&social_url/1) |> Enum.uniq()

    {emails, socials} =
      if listing?,
        do: drop_directory_contacts(emails, socials, source_url),
        else: {emails, socials}

    contacts =
      Enum.map(emails, &%{type: :email, value: &1, source_url: source_url}) ++
        Enum.map(phones, &%{type: :phone, value: &1, source_url: source_url}) ++
        Enum.map(socials, &%{type: :social, value: &1, source_url: source_url})

    %{contacts: contacts, text: text, title: title}
  end

  defp page_title(html) do
    case html
         |> LazyHTML.from_document()
         |> LazyHTML.query("title")
         |> LazyHTML.text()
         |> squish() do
      "" -> nil
      title -> title
    end
  end

  # LazyHTML.text/1 includes script and style contents; drop them first.
  defp strip_non_content(html) do
    Regex.replace(~r/<(script|style|noscript|svg|template)\b[^>]*>.*?<\/\1\s*>/is, html, " ")
  end

  defp strip_site_chrome(html) do
    Regex.replace(~r/<(header|footer|nav|aside)\b[^>]*>.*?<\/\1\s*>/is, html, " ")
  end

  # LazyHTML.text/1 joins adjacent elements without a space, which glues
  # "info@acme.com" in one cell onto "Phone" in the next. Put a space before
  # every tag except inline formatting ones that may split a word.
  defp space_out_tags(html) do
    Regex.replace(~r/<(?!\/?(?:b|i|em|strong|u|sup|sub|small|mark|abbr)\b)/i, html, " <")
  end

  defp drop_directory_contacts(emails, socials, source_url) do
    host = URI.parse(source_url).host || ""
    label = host |> String.replace_prefix("www.", "") |> String.split(".") |> hd()

    emails =
      Enum.reject(emails, &UrlGuard.same_site?(&1 |> String.split("@") |> List.last(), host))

    socials =
      if String.length(label) >= 4,
        do: Enum.reject(socials, &String.contains?(String.downcase(&1), label)),
        else: socials

    {emails, socials}
  end

  defp visible_text(doc) do
    body = LazyHTML.query(doc, "body")
    node = if Enum.empty?(body), do: doc, else: body
    node |> LazyHTML.text() |> squish()
  end

  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  ## Emails

  defp mailto_emails(hrefs) do
    Enum.flat_map(hrefs, fn href ->
      case Regex.run(~r/^\s*mailto:([^?]+)/i, href) do
        [_, addresses] ->
          addresses
          |> safe_decode()
          |> String.split([",", ";"])
          |> Enum.map(&(&1 |> String.trim() |> String.downcase()))

        _ ->
          []
      end
    end)
  end

  defp text_emails(text) do
    text = deobfuscate(text)

    @email_regex
    |> Regex.scan(text)
    |> Enum.map(fn [email] -> email |> String.downcase() |> String.trim_trailing(".") end)
  end

  @doc false
  # Handles `name [at] domain [dot] com`, `name(at)domain.com`, `name at domain dot com`.
  def deobfuscate(text) do
    text
    |> String.replace(~r/\s*[\[\(\{<]\s*at\s*[\]\)\}>]\s*/i, "@")
    |> String.replace(~r/\s*[\[\(\{<]\s*dot\s*[\]\)\}>]\s*/i, ".")
    |> String.replace(
      ~r/\b([a-z0-9._%+-]+)\s+at\s+([a-z0-9-]+)\s+dot\s+([a-z]{2,24})\b/i,
      "\\1@\\2.\\3"
    )
  end

  defp valid_email?(email) do
    with [local, domain] <- String.split(email, "@"),
         true <- Regex.match?(@email_regex, email),
         false <- Enum.any?(@asset_extensions, &String.ends_with?(email, &1)),
         false <- domain in @ignored_email_domains,
         false <- String.ends_with?(domain, ".wixpress.com"),
         # Sentry/tracking addresses are long hex strings
         false <- String.length(local) >= 24 and local =~ ~r/^[a-f0-9]+$/ do
      true
    else
      _ -> false
    end
  end

  ## Phones

  defp tel_phones(hrefs) do
    Enum.flat_map(hrefs, fn href ->
      case Regex.run(~r/^\s*tel:(.+)/i, href) do
        [_, number] -> number |> safe_decode() |> normalize_phone() |> List.wrap()
        _ -> []
      end
    end)
  end

  defp text_phones(text) do
    @phone_keyword_regex
    |> Regex.scan(text)
    |> Enum.flat_map(fn [_, number] -> number |> normalize_phone() |> List.wrap() end)
  end

  @doc """
  Normalizes a phone number: keeps a leading `+` and digits only. `00` is
  treated as an international prefix. Returns nil if it isn't 7–15 digits.
  """
  @spec normalize_phone(String.t()) :: String.t() | nil
  def normalize_phone(raw) do
    raw = String.trim(raw)
    digits = String.replace(raw, ~r/\D/, "")

    {plus, digits} =
      cond do
        String.starts_with?(raw, "+") -> {"+", digits}
        String.starts_with?(digits, "00") -> {"+", String.slice(digits, 2..-1//1)}
        true -> {"", digits}
      end

    if String.length(digits) in 7..15, do: plus <> digits, else: nil
  end

  defp safe_decode(value) do
    URI.decode(value)
  rescue
    ArgumentError -> value
  end

  ## Social

  defp social_url(href) do
    with {:ok, uri} <- URI.new(String.trim(href)),
         true <- uri.scheme in ["http", "https"],
         host when is_binary(host) <- uri.host,
         bare = host |> String.downcase() |> String.replace(~r/^(www|m|mobile|[a-z]{2})\./, ""),
         true <- Map.has_key?(@social_hosts, bare),
         path when path not in [nil, "", "/"] <- uri.path,
         false <- Regex.match?(@social_skip, path) do
      ["https://#{bare}#{String.trim_trailing(path, "/")}"]
    else
      _ -> []
    end
  end
end
