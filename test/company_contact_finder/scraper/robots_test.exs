defmodule CompanyContactFinder.Scraper.RobotsTest do
  use ExUnit.Case, async: true

  alias CompanyContactFinder.Scraper.Robots

  test "applies * rules" do
    rules = Robots.parse("User-agent: *\nDisallow: /private\nDisallow: /tmp/ # comment\n")

    refute Robots.allowed?(rules, "/private/team")
    refute Robots.allowed?(rules, "/tmp/x")
    assert Robots.allowed?(rules, "/contact")
  end

  test "prefers a group for our bot over *" do
    rules =
      Robots.parse("""
      User-agent: *
      Disallow: /

      User-agent: GS1KenyaLeadFinder
      Disallow: /admin
      """)

    assert Robots.allowed?(rules, "/contact")
    refute Robots.allowed?(rules, "/admin")
  end

  test "longest match wins and Allow can override" do
    rules = Robots.parse("User-agent: *\nDisallow: /about\nAllow: /about/contact\n")

    assert Robots.allowed?(rules, "/about/contact")
    refute Robots.allowed?(rules, "/about/history")
  end

  test "empty or missing robots.txt allows everything" do
    assert Robots.allowed?(Robots.parse(nil), "/anything")
    assert Robots.allowed?(Robots.parse("User-agent: *\nDisallow:\n"), "/anything")
  end
end
