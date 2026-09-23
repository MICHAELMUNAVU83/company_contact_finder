defmodule CompanyContactFinder.LeadsTest do
  use CompanyContactFinder.DataCase, async: true

  import CompanyContactFinder.LeadStubs

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Lookup

  defp await_done(id) do
    Leads.subscribe_lookup(id)

    # The run may already have finished before we subscribed.
    unless Repo.get!(Lookup, id).status in [:done, :failed] do
      assert_receive {:lookup_updated, %{status: status}} when status in [:done, :failed], 2_000
    end

    Leads.get_lookup!(id)
  end

  describe "start_lookup/1" do
    test "validates the company name" do
      assert {:error, changeset} = Leads.start_lookup(%{"company_name" => " "})
      assert "can't be blank" in errors_on(changeset).company_name
    end

    test "squishes whitespace and runs in the background" do
      stub_all()
      Leads.subscribe_lookups()

      assert {:ok, lookup} = Leads.start_lookup(%{"company_name" => "  Acme   Logistics "})
      assert lookup.company_name == "Acme Logistics"
      assert_receive {:lookup_updated, %{id: id, status: :pending}} when id == lookup.id

      assert await_done(lookup.id).status == :done
    end
  end

  test "start_bulk_lookups/1 creates one lookup per unique name" do
    stub_all()

    assert {:ok, lookups} = Leads.start_bulk_lookups("Acme\nacme\nGlobex, Initech\n\nx")
    assert Enum.map(lookups, & &1.company_name) == ["Acme", "Globex", "Initech"]

    for lookup <- lookups, do: await_done(lookup.id)
  end

  describe "reruns" do
    setup do
      stub_all()
      {:ok, lookup} = Leads.start_lookup(%{"company_name" => "Acme Logistics"})
      %{lookup: await_done(lookup.id)}
    end

    test "rerun_with_website/2 validates the url", %{lookup: lookup} do
      assert {:error, changeset} =
               Leads.rerun_with_website(lookup, %{"website_url" => "http://localhost"})

      assert "must be a public http(s) website" in errors_on(changeset).website_url
    end

    test "rerun_with_website/2 crawls the new site and clears old results", %{lookup: lookup} do
      assert {:ok, rerun} =
               Leads.rerun_with_website(lookup, %{
                 "website_url" => "https://acmelogistics.co.ke/about"
               })

      assert rerun.website_overridden

      lookup = await_done(lookup.id)
      assert lookup.status == :done
      assert lookup.website_url == "https://acmelogistics.co.ke"
      assert lookup.contacts != []
    end

    test "rerun_with_website/2 keeps a directory listing url and fetches only that page", %{
      lookup: lookup
    } do
      stub_site(Map.put(default_pages(), "/business/acme", fixture("listing.html")))

      assert {:ok, rerun} =
               Leads.rerun_with_website(lookup, %{
                 "website_url" => "www.yellowpageskenya.com/business/acme"
               })

      assert rerun.source == :listing

      lookup = await_done(lookup.id)
      assert lookup.website_url == "https://www.yellowpageskenya.com/business/acme"
      assert lookup.pages_crawled == 1
      assert "info@elys.co.ke" in for(%{type: :email, value: v} <- lookup.contacts, do: v)
      refute Enum.any?(lookup.contacts, &(&1.value =~ "yellowpageskenya"))
    end

    test "rerun_with_website/2 rejects a directory's homepage", %{lookup: lookup} do
      assert {:error, changeset} =
               Leads.rerun_with_website(lookup, %{"website_url" => "www.yellowpageskenya.com"})

      assert [message] = errors_on(changeset).website_url
      assert message =~ "directory"
    end

    test "refuses to rerun a lookup that is still running", %{lookup: lookup} do
      lookup |> Lookup.progress_changeset(%{status: :crawling}) |> Repo.update!()
      assert Leads.rerun_lookup(lookup) == {:error, :in_progress}
      assert Leads.retry_brief(lookup) == {:error, :in_progress}
    end
  end

  test "list_lookups/1 includes contact counts and sorts by score" do
    low = Repo.insert!(%Lookup{company_name: "Low", status: :done})
    high = Repo.insert!(%Lookup{company_name: "High", status: :done})
    none = Repo.insert!(%Lookup{company_name: "None", status: :failed})
    Leads.save_brief(low, %{status: :done, lead_score: 10})
    Leads.save_brief(high, %{status: :done, lead_score: 90})

    Leads.add_contacts(high, [
      %{type: :email, value: "a@high.com", source_url: "https://high.com"}
    ])

    assert [%{id: h, contact_count: 1}, %{id: l}, %{id: n}] = Leads.list_lookups(sort: :score)
    assert {h, l, n} == {high.id, low.id, none.id}
  end

  test "add_contacts/2 skips duplicates" do
    lookup = Repo.insert!(%Lookup{company_name: "Acme"})
    contact = %{type: :email, value: "a@acme.com", source_url: "https://acme.com"}

    assert [_] = Leads.add_contacts(lookup, [contact, contact])
    assert [] = Leads.add_contacts(lookup, [contact])
  end
end
