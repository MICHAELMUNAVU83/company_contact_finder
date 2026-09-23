defmodule CompanyContactFinder.Scraper.UrlGuardTest do
  use ExUnit.Case, async: true

  alias CompanyContactFinder.Scraper.UrlGuard

  test "normalize_root/1 returns the site root" do
    assert UrlGuard.normalize_root("https://www.Acme.com/about?x=1") ==
             {:ok, "https://www.acme.com"}

    assert UrlGuard.normalize_root("acme.co.ke") == {:ok, "https://acme.co.ke"}
    assert UrlGuard.normalize_root("http://acme.com:8080/") == {:ok, "http://acme.com:8080"}
  end

  test "rejects non-http schemes and junk" do
    assert UrlGuard.parse("ftp://acme.com") == {:error, :unsupported_scheme}
    assert UrlGuard.parse("javascript:alert(1)") == {:error, :invalid_url}
    assert {:error, _} = UrlGuard.parse("")
    assert {:error, _} = UrlGuard.parse("https://intranet")
  end

  test "rejects private and local hosts" do
    for url <- [
          "http://localhost:4000",
          "http://127.0.0.1",
          "http://10.0.0.5",
          "http://192.168.1.1",
          "http://172.16.0.1",
          "http://169.254.169.254/latest/meta-data",
          "http://[::1]/",
          "http://[::ffff:127.0.0.1]/",
          "http://printer.local"
        ] do
      assert UrlGuard.parse(url) == {:error, :private_host}, url
    end
  end

  test "allows public IPs" do
    assert {:ok, %URI{host: "8.8.8.8"}} = UrlGuard.parse("http://8.8.8.8")
  end

  test "same_site?/2 ignores www" do
    assert UrlGuard.same_site?("www.acme.com", "acme.com")
    refute UrlGuard.same_site?("acme.com", "evil.com")
    refute UrlGuard.same_site?(nil, "acme.com")
  end
end
