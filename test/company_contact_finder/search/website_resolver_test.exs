defmodule CompanyContactFinder.Search.WebsiteResolverTest do
  use ExUnit.Case, async: true

  alias CompanyContactFinder.Search.WebsiteResolver

  test "prefers the knowledge graph website" do
    body = %{
      "knowledgeGraph" => %{"website" => "https://www.acme.com/en"},
      "organic" => [%{"link" => "https://acme-fans.com", "position" => 1}]
    }

    assert {:ok, "https://www.acme.com", [first | _]} = WebsiteResolver.resolve("Acme", body)
    assert first["source"] == "knowledge_graph"
  end

  test "skips directories and social sites" do
    body = %{
      "organic" => [
        %{"link" => "https://www.linkedin.com/company/acme", "position" => 1},
        %{"link" => "https://en.wikipedia.org/wiki/Acme", "position" => 2},
        %{"link" => "https://www.crunchbase.com/organization/acme", "position" => 3},
        %{"link" => "https://acme.io/", "position" => 4}
      ]
    }

    assert {:ok, "https://acme.io", candidates} = WebsiteResolver.resolve("Acme Inc", body)
    assert Enum.map(candidates, & &1["host"]) == ["acme.io"]
  end

  test "boosts domains that match the company name" do
    body = %{
      "organic" => [
        %{"link" => "https://logisticsnews.com/acme-review", "position" => 1},
        %{"link" => "https://acmelogistics.co.ke", "position" => 2}
      ]
    }

    assert {:ok, "https://acmelogistics.co.ke", _} =
             WebsiteResolver.resolve("Acme Logistics Ltd", body)
  end

  test "prefers Kenyan domains when the name matches equally" do
    body = %{
      "organic" => [
        %{"link" => "https://acme.com", "position" => 1},
        %{"link" => "https://acme.co.ke", "position" => 2}
      ]
    }

    assert {:ok, "https://acme.co.ke", _} = WebsiteResolver.resolve("Acme", body)
  end

  test "returns an error when nothing is usable" do
    assert WebsiteResolver.resolve("Acme", %{"organic" => []}) == {:error, :no_website}
    assert WebsiteResolver.resolve("Acme", %{}) == {:error, :no_website}
  end

  test "name_tokens/1 drops legal suffixes and punctuation" do
    assert WebsiteResolver.name_tokens("Acme Logistics (Kenya) Ltd.") == ["acme", "logistics"]
  end

  describe "resolve_listing/2" do
    test "picks a directory page whose title names the company" do
      body = %{
        "organic" => [
          %{
            "title" => "Yellow Pages Kenya - Business Directory",
            "link" => "https://www.yellowpageskenya.com/",
            "position" => 1
          },
          %{
            "title" => "Acme Plastics - Yellow Pages Kenya",
            "link" => "https://www.yellowpageskenya.com/business/acme-plastics",
            "position" => 2
          },
          %{
            "title" => "Elys Chemical Industries Ltd - Yellow Pages Kenya",
            "link" => "https://www.yellowpageskenya.com/business/elys-chemical#top",
            "position" => 3
          }
        ]
      }

      assert {:ok, "https://www.yellowpageskenya.com/business/elys-chemical"} =
               WebsiteResolver.resolve_listing("Elys Chemicals Industries Limited", body)

      assert {:error, :no_website} = WebsiteResolver.resolve("Elys Chemicals Industries", body)
    end

    test "ignores social sites and unrelated listings" do
      body = %{
        "organic" => [
          %{
            "title" => "Elys Chemical Industries | LinkedIn",
            "link" => "https://www.linkedin.com/company/elys",
            "position" => 1
          },
          %{
            "title" => "Other Chemicals Ltd - BusinessList",
            "link" => "https://www.businesslist.co.ke/company/1/other",
            "position" => 2
          }
        ]
      }

      assert {:error, :no_website} =
               WebsiteResolver.resolve_listing("Elys Chemicals Industries Limited", body)
    end
  end
end
