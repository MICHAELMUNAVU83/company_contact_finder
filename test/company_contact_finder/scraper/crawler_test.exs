defmodule CompanyContactFinder.Scraper.CrawlerTest do
  use ExUnit.Case, async: true

  alias CompanyContactFinder.LeadStubs
  alias CompanyContactFinder.Scraper.Crawler

  test "fetches the homepage then contact-like pages on the same site" do
    LeadStubs.stub_site()

    assert {:ok, [home | rest]} = Crawler.crawl("https://acmelogistics.co.ke")
    assert home.url == "https://acmelogistics.co.ke/"

    urls = Enum.map(rest, & &1.url)
    assert "https://acmelogistics.co.ke/get-in-touch" in urls
    assert "https://acmelogistics.co.ke/about-us" in urls
    refute Enum.any?(urls, &String.contains?(&1, "other-site.com"))
    refute Enum.any?(urls, &String.ends_with?(&1, ".pdf"))
    refute Enum.any?(urls, &String.contains?(&1, "/blog"))
  end

  test "respects robots.txt" do
    LeadStubs.stub_site(%{
      "/robots.txt" => {:text, "User-agent: *\nDisallow: /get-in-touch\n"},
      "/" => LeadStubs.fixture("home.html"),
      "/get-in-touch" => LeadStubs.fixture("contact.html")
    })

    {:ok, pages} = Crawler.crawl("https://acmelogistics.co.ke")
    refute Enum.any?(pages, &String.ends_with?(&1.url, "/get-in-touch"))
  end

  test "respects the page limit" do
    LeadStubs.stub_site()
    {:ok, pages} = Crawler.crawl("https://acmelogistics.co.ke", max_pages: 2)
    assert length(pages) <= 2
  end

  test "follows redirects but refuses to follow them to private hosts" do
    LeadStubs.stub_site(%{"/" => {:redirect, "http://127.0.0.1/admin"}})
    assert Crawler.crawl("https://acmelogistics.co.ke") == {:error, :private_host}
  end

  test "follows same-site redirects" do
    LeadStubs.stub_site(%{
      "/" => {:redirect, "/home"},
      "/home" => "<html><body><a href=\"mailto:a@b.co\">x</a></body></html>"
    })

    assert {:ok, [%{url: "https://acmelogistics.co.ke/home"} | _]} =
             Crawler.crawl("https://acmelogistics.co.ke")
  end

  test "fails when the homepage can't be fetched" do
    LeadStubs.stub_site(%{})
    assert Crawler.crawl("https://acmelogistics.co.ke") == {:error, {:http_error, 404}}
  end
end
