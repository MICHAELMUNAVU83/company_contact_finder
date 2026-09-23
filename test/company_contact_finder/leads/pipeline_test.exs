defmodule CompanyContactFinder.Leads.PipelineTest do
  use CompanyContactFinder.DataCase, async: true

  import CompanyContactFinder.LeadStubs

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.{Lookup, Pipeline}

  defp insert_lookup(attrs \\ %{}) do
    %Lookup{}
    |> Lookup.create_changeset(Map.merge(%{"company_name" => "Acme Logistics"}, attrs))
    |> Repo.insert!()
  end

  test "searches, crawls, extracts contacts and writes a brief" do
    stub_all()
    lookup = insert_lookup()

    Pipeline.run(lookup.id)

    lookup = Leads.get_lookup!(lookup.id)
    assert lookup.status == :done
    assert lookup.website_url == "https://acmelogistics.co.ke"
    assert lookup.query == "Acme Logistics Kenya official website"
    assert lookup.pages_crawled >= 2
    assert lookup.scraped_text =~ "freight across East Africa"
    assert [%{"host" => "acmelogistics.co.ke"} | _] = lookup.candidates

    emails = for %{type: :email, value: v} <- lookup.contacts, do: v
    assert "info@acmelogistics.co.ke" in emails
    assert "sales@acmelogistics.co.ke" in emails
    assert Enum.any?(lookup.contacts, &(&1.type == :phone))
    assert Enum.any?(lookup.contacts, &(&1.type == :social))

    assert lookup.brief.status == :done
    assert lookup.brief.lead_score == 78
    assert lookup.brief.industry == "Logistics"
    assert lookup.brief.best_contact == "sales@acmelogistics.co.ke"
    assert lookup.brief.prompt_tokens == 1200
    assert lookup.brief.model == "test-model"

    sales = Enum.find(lookup.contacts, &(&1.value == "sales@acmelogistics.co.ke"))
    assert sales.role == "sales"
    assert sales.quality == "high"
  end

  test "scopes the search to Kenya" do
    test_pid = self()

    Req.Test.stub(CompanyContactFinder.Search.Serper, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:serper_request, Jason.decode!(body)})
      Req.Test.json(conn, serper_body())
    end)

    stub_site()
    stub_openai()
    lookup = insert_lookup(%{"company_name" => "Acme Kenya Ltd"})

    Pipeline.run(lookup.id)

    assert_receive {:serper_request, %{"q" => "Acme Kenya Ltd official website", "gl" => "ke"}}
  end

  test "falls back to a directory listing when the company has no website" do
    stub_serper(%{
      "organic" => [
        %{
          "title" => "Elys Chemical Industries Ltd - Yellow Pages Kenya",
          "link" => "https://www.yellowpageskenya.com/business/elys",
          "position" => 1
        }
      ]
    })

    stub_site(%{"/business/elys" => fixture("listing.html")})
    stub_openai()
    lookup = insert_lookup(%{"company_name" => "Elys Chemicals Industries Limited"})

    Pipeline.run(lookup.id)

    lookup = Leads.get_lookup!(lookup.id)
    assert lookup.status == :done
    assert lookup.source == :listing
    assert lookup.website_url == "https://www.yellowpageskenya.com/business/elys"
    assert lookup.pages_crawled == 1

    assert Enum.map(lookup.contacts, & &1.value) |> Enum.sort() ==
             ["+254722000111", "https://facebook.com/elyschemicals", "info@elys.co.ke"]
  end

  test "ignores AI analysis for contacts that weren't scraped" do
    stub_all()
    lookup = insert_lookup()
    Pipeline.run(lookup.id)

    lookup = Leads.get_lookup!(lookup.id)
    refute Enum.any?(lookup.contacts, &(&1.value == "made-up@nowhere.com"))
  end

  test "drops a best_contact the model invented" do
    stub_serper()
    stub_site()
    stub_openai(brief_content(%{"best_contact" => "ceo@invented.com"}))
    lookup = insert_lookup()

    Pipeline.run(lookup.id)

    assert Leads.get_lookup!(lookup.id).brief.best_contact == nil
  end

  test "finishes with contacts when OpenAI fails" do
    stub_serper()
    stub_site()
    stub_openai_error(500)
    lookup = insert_lookup()

    Pipeline.run(lookup.id)

    lookup = Leads.get_lookup!(lookup.id)
    assert lookup.status == :done
    assert lookup.contacts != []
    assert lookup.brief.status == :failed
    assert lookup.brief.error =~ "HTTP 500"
  end

  test "retrying the brief reuses the scraped text" do
    stub_serper()
    stub_site()
    stub_openai_error(429)
    lookup = insert_lookup()
    Pipeline.run(lookup.id)

    stub_openai()
    Pipeline.analyse(lookup.id)

    assert Leads.get_lookup!(lookup.id).brief.status == :done
  end

  test "fails the lookup when search fails" do
    stub_serper_error(401)
    lookup = insert_lookup()

    Pipeline.run(lookup.id)

    lookup = Repo.get!(Lookup, lookup.id)
    assert lookup.status == :failed
    assert lookup.error == "Serper rejected the API key"
  end

  test "fails the lookup when no website is found" do
    stub_serper(%{"organic" => [%{"link" => "https://www.linkedin.com/company/acme"}]})
    lookup = insert_lookup()

    Pipeline.run(lookup.id)

    assert Repo.get!(Lookup, lookup.id).error =~ "Couldn't find an official website"
  end

  test "fails the lookup when the website is unreachable" do
    stub_serper()
    stub_site(%{})
    lookup = insert_lookup()

    Pipeline.run(lookup.id)

    lookup = Repo.get!(Lookup, lookup.id)
    assert lookup.status == :failed
    assert lookup.error == "Website returned HTTP 404"
  end

  test "skips search when the website was set manually" do
    # No Serper stub: a search would raise.
    stub_site()
    stub_openai()

    lookup =
      insert_lookup()
      |> Lookup.website_changeset(%{"website_url" => "acmelogistics.co.ke"})
      |> Repo.update!()

    Pipeline.run(lookup.id)

    assert Repo.get!(Lookup, lookup.id).status == :done
  end

  test "broadcasts progress" do
    stub_all()
    lookup = insert_lookup()
    Leads.subscribe_lookup(lookup.id)

    Pipeline.run(lookup.id)

    assert_received {:lookup_updated, %{status: :searching}}
    assert_received {:lookup_updated, %{status: :crawling}}
    assert_received {:contacts_added, [_ | _]}
    assert_received {:brief_updated, %{status: :done}}
    assert_received {:lookup_updated, %{status: :done}}
  end
end
