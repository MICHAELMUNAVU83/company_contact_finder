defmodule CompanyContactFinderWeb.LookupLiveTest do
  use CompanyContactFinderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CompanyContactFinder.LeadStubs

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Lookup
  alias CompanyContactFinder.Repo

  defp await_done(id) do
    Leads.subscribe_lookup(id)

    unless Repo.get!(Lookup, id).status in [:done, :failed] do
      assert_receive {:lookup_updated, %{status: status}} when status in [:done, :failed], 2_000
    end
  end

  describe "Index" do
    test "shows the empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#lookup-form")
      assert has_element?(view, "#lookups-empty")
    end

    test "validates the company name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#lookup-form", lookup: %{company_name: "a"}) |> render_change()
      assert has_element?(view, "#lookup-form p", "should be at least 2 character(s)")
    end

    test "starting a lookup navigates to its page", %{conn: conn} do
      stub_all()
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#lookup-form", lookup: %{company_name: "Acme Logistics"}) |> render_submit()

      lookup = Repo.one!(Lookup)
      assert_redirect(view, ~p"/lookups/#{lookup}")
      await_done(lookup.id)
    end

    test "bulk mode queues many lookups", %{conn: conn} do
      stub_all()
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#mode-bulk") |> render_click()
      view |> form("#bulk-form", bulk: %{names: "Acme\nGlobex"}) |> render_submit()

      lookups = Repo.all(Lookup)
      assert length(lookups) == 2
      for lookup <- lookups, do: await_done(lookup.id)
    end

    test "lists lookups and updates them live", %{conn: conn} do
      lookup = Repo.insert!(%Lookup{company_name: "Acme", status: :crawling})
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#lookups-#{lookup.id}", "Acme")
      assert has_element?(view, "#lookups-#{lookup.id}", "Crawling")

      Leads.update_progress(lookup, %{status: :done})
      assert has_element?(view, "#lookups-#{lookup.id}", "Done")
    end

    test "sorts by lead score", %{conn: conn} do
      low = Repo.insert!(%Lookup{company_name: "Low", status: :done})
      high = Repo.insert!(%Lookup{company_name: "High", status: :done})
      Leads.save_brief(low, %{status: :done, lead_score: 10})
      Leads.save_brief(high, %{status: :done, lead_score: 90})

      {:ok, view, _html} = live(conn, ~p"/?sort=score")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#lookups > li[id^='lookups-']:not(#lookups-empty)")
        |> LazyHTML.attribute("id")

      assert ids == ["lookups-#{high.id}", "lookups-#{low.id}"]
    end
  end

  describe "Show" do
    test "shows contacts and the brief as the run progresses", %{conn: conn} do
      stub_all()
      lookup = Repo.insert!(%Lookup{company_name: "Acme Logistics"})
      {:ok, view, _html} = live(conn, ~p"/lookups/#{lookup}")

      assert has_element?(view, "#brief-loading")

      CompanyContactFinder.Leads.Pipeline.run(lookup.id)

      assert has_element?(view, "#lookup-status", "Done")
      assert has_element?(view, "#emails li", "sales@acmelogistics.co.ke")
      assert has_element?(view, "#phones li", "+254700123456")
      assert has_element?(view, "#socials li", "linkedin.com/company/acme-logistics")
      assert has_element?(view, "#brief", "Logistics")
      assert has_element?(view, "#brief", "78")
    end

    test "shows a failed lookup's error", %{conn: conn} do
      lookup =
        Repo.insert!(%Lookup{
          company_name: "Acme",
          status: :failed,
          error: "Website returned HTTP 404"
        })

      {:ok, view, _html} = live(conn, ~p"/lookups/#{lookup}")

      assert has_element?(view, "#lookup-error", "Website returned HTTP 404")
    end

    test "a failed brief can be retried", %{conn: conn} do
      stub_serper()
      stub_site()
      stub_openai_error(500)
      lookup = Repo.insert!(%Lookup{company_name: "Acme Logistics"})
      CompanyContactFinder.Leads.Pipeline.run(lookup.id)

      {:ok, view, _html} = live(conn, ~p"/lookups/#{lookup}")
      assert has_element?(view, "#brief-failed")

      stub_openai()
      view |> element("#retry-brief-button") |> render_click()
      await_done(lookup.id)

      assert has_element?(view, "#brief")
    end

    test "rejects a private website override", %{conn: conn} do
      lookup = Repo.insert!(%Lookup{company_name: "Acme", status: :done})
      {:ok, view, _html} = live(conn, ~p"/lookups/#{lookup}")

      view
      |> form("#website-form", lookup: %{website_url: "http://169.254.169.254"})
      |> render_submit()

      assert has_element?(view, "#website-form", "must be a public http(s) website")
    end

    test "a website override re-crawls that site", %{conn: conn} do
      stub_site()
      stub_openai()

      lookup =
        Repo.insert!(%Lookup{
          company_name: "Acme",
          status: :done,
          website_url: "https://wrong.com"
        })

      {:ok, view, _html} = live(conn, ~p"/lookups/#{lookup}")

      view
      |> form("#website-form", lookup: %{website_url: "acmelogistics.co.ke"})
      |> render_submit()

      await_done(lookup.id)
      assert has_element?(view, "#lookup-status", "Done")
      assert has_element?(view, "#emails li", "info@acmelogistics.co.ke")
      assert Repo.get!(Lookup, lookup.id).website_url == "https://acmelogistics.co.ke"
    end
  end
end
