defmodule CompanyContactFinder.Scraper.ExtractorTest do
  use ExUnit.Case, async: true

  alias CompanyContactFinder.LeadStubs
  alias CompanyContactFinder.Scraper.Extractor

  defp values(result, type), do: for(%{type: ^type, value: v} <- result.contacts, do: v)

  describe "extract/2 on the homepage fixture" do
    setup do
      %{result: Extractor.extract(LeadStubs.fixture("home.html"), "https://acmelogistics.co.ke/")}
    end

    test "reads mailto links and ignores placeholder and asset addresses", %{result: result} do
      assert values(result, :email) == ["info@acmelogistics.co.ke"]
    end

    test "ignores text inside script and style tags", %{result: result} do
      refute result.text =~ "tracking"
      refute "noise@tracker.io" in values(result, :email)
    end

    test "normalizes tel links", %{result: result} do
      assert values(result, :phone) == ["+254700123456"]
    end

    test "keeps profile links and drops share links", %{result: result} do
      assert values(result, :social) == [
               "https://linkedin.com/company/acme-logistics",
               "https://twitter.com/acmelogistics"
             ]
    end

    test "records the source url and page title", %{result: result} do
      assert Enum.all?(result.contacts, &(&1.source_url == "https://acmelogistics.co.ke/"))
      assert result.title == "Acme Logistics | Freight forwarding in Nairobi"
    end
  end

  describe "extract/2 on the contact fixture" do
    setup do
      %{
        result:
          Extractor.extract(
            LeadStubs.fixture("contact.html"),
            "https://acmelogistics.co.ke/contact"
          )
      }
    end

    test "decodes obfuscated emails and dedupes case-insensitively", %{result: result} do
      emails = values(result, :email)

      assert "sales@acmelogistics.co.ke" in emails
      assert "support@acmelogistics.co.ke" in emails
      assert "jobs@acmelogistics.co.ke" in emails
      assert "info@acmelogistics.co.ke" in emails
      assert length(emails) == length(Enum.uniq(emails))
    end

    test "drops tracking addresses", %{result: result} do
      refute Enum.any?(values(result, :email), &String.contains?(&1, "sentry"))
    end

    test "finds phone numbers next to keywords only", %{result: result} do
      phones = values(result, :phone)

      assert "0711222333" in phones
      assert "+254205556666" in phones
      refute "12345" in phones
    end
  end

  describe "normalize_phone/1" do
    test "handles international formats" do
      assert Extractor.normalize_phone("+254 (0) 700-123-456") == "+2540700123456"
      assert Extractor.normalize_phone("00 44 20 7946 0958") == "+442079460958"
      assert Extractor.normalize_phone("020 555 1234") == "0205551234"
    end

    test "rejects numbers that are too short or long" do
      assert Extractor.normalize_phone("12345") == nil
      assert Extractor.normalize_phone("1234567890123456") == nil
    end
  end

  test "deobfuscate/1" do
    assert Extractor.deobfuscate("jane at acme dot com") == "jane@acme.com"
    assert Extractor.deobfuscate("jane {at} acme {dot} com") == "jane@acme.com"
  end

  test "keeps text from adjacent elements apart" do
    html =
      "<table><tr><td>info@acme.com</td><td>Phone</td><td>0000</td><td>jobs@acme.com</td></tr></table>"

    result = Extractor.extract(html, "https://acme.com/")

    assert values(result, :email) == ["info@acme.com", "jobs@acme.com"]
  end

  describe "extract/3 on a directory listing" do
    setup do
      url = "https://www.yellowpageskenya.com/business/elys-chemical-industries"
      %{result: Extractor.extract(LeadStubs.fixture("listing.html"), url, listing: true)}
    end

    test "keeps the company's contacts and drops the directory's", %{result: result} do
      assert values(result, :email) == ["info@elys.co.ke"]
      assert values(result, :phone) == ["+254722000111"]
      assert values(result, :social) == ["https://facebook.com/elyschemicals"]
    end

    test "drops the site's header, footer and sidebar text", %{result: result} do
      assert result.text =~ "detergents and soaps"
      refute result.text =~ "Similar companies"
      assert result.title == "Elys Chemical Industries Ltd - Yellow Pages Kenya"
    end
  end
end
