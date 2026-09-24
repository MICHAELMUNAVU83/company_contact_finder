defmodule CompanyContactFinderWeb.BucketLiveTest do
  use CompanyContactFinderWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import CompanyContactFinder.LeadStubs

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.{Bucket, Lookup}
  alias CompanyContactFinder.Repo

  defp await_done(id) do
    Leads.subscribe_lookup(id)

    unless Repo.get!(Lookup, id).status in [:done, :failed] do
      assert_receive {:lookup_updated, %{status: status}} when status in [:done, :failed], 2_000
    end
  end

  test "index shows the empty state and bucket cards", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/buckets")
    assert has_element?(view, "#buckets-empty")

    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    {:ok, view, _html} = live(conn, ~p"/buckets")
    assert has_element?(view, "#buckets-#{bucket.id}", "Nairobi logistics firms")
  end

  test "creating a bucket", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/buckets/new")

    view |> form("#bucket-form", bucket: %{name: ""}) |> render_change()
    assert has_element?(view, "#bucket-form", "can't be blank")

    view |> element("button[phx-value-service='GS1 standards training']") |> render_click()
    view |> element("button[phx-value-service='SSCC logistics labels']") |> render_click()
    view |> element("button[phx-value-service='Traceability solutions']") |> render_click()
    view |> element("button[phx-value-service='Traceability solutions']") |> render_click()

    view
    |> form("#bucket-form",
      bucket: %{
        name: "Food makers",
        target_description: "Packaged food manufacturers",
        industries: "Food, Beverages",
        company_sizes: ["small"]
      }
    )
    |> render_submit()

    bucket = Repo.one!(Bucket)
    assert bucket.services == ["GS1 standards training", "SSCC logistics labels"]
    assert bucket.industries == ["Food", "Beverages"]
    assert bucket.company_sizes == ["small"]
    assert_redirect(view, ~p"/buckets/#{bucket}")
  end

  test "editing a bucket", %{conn: conn} do
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    {:ok, view, _html} = live(conn, ~p"/buckets/#{bucket}/edit")

    view |> form("#bucket-form", bucket: %{name: "Renamed"}) |> render_submit()

    assert Leads.get_bucket!(bucket.id).name == "Renamed"
    assert_redirect(view, ~p"/buckets/#{bucket}")
  end

  test "show ranks leads and adds companies", %{conn: conn} do
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    low = Repo.insert!(%Lookup{company_name: "Low Co", bucket_id: bucket.id, status: :done})
    high = Repo.insert!(%Lookup{company_name: "High Co", bucket_id: bucket.id, status: :done})

    Leads.save_brief(low, %{
      status: :done,
      lead_score: 20,
      fit: "weak",
      scored_bucket_id: bucket.id,
      scored_at: DateTime.utc_now(:second)
    })

    Leads.save_brief(high, %{
      status: :done,
      lead_score: 90,
      fit: "strong",
      scored_bucket_id: bucket.id,
      scored_at: DateTime.utc_now(:second)
    })

    {:ok, view, _html} = live(conn, ~p"/buckets/#{bucket}")
    assert has_element?(view, "#bucket-criteria", "SSCC logistics labels")

    ids =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#bucket-leads > li[id^='leads-']")
      |> LazyHTML.attribute("id")

    assert ids == ["leads-#{high.id}", "leads-#{low.id}"]
    assert has_element?(view, "#leads-#{high.id}", "Strong fit")

    stub_all()
    view |> form("#add-companies-form", add: %{names: "Acme Logistics"}) |> render_submit()

    added = Repo.get_by!(Lookup, company_name: "Acme Logistics")
    assert added.bucket_id == bucket.id
    await_done(added.id)
    assert has_element?(view, "#leads-#{added.id}")
  end

  test "deleting a bucket", %{conn: conn} do
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    {:ok, view, _html} = live(conn, ~p"/buckets/#{bucket}")

    view |> element("#delete-bucket") |> render_click()

    assert_redirect(view, ~p"/buckets")
    assert Repo.all(Bucket) == []
  end

  test "moving a lookup into a bucket from its page rescores it", %{conn: conn} do
    stub_all()
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    lookup = Repo.insert!(%Lookup{company_name: "Acme Logistics"})
    CompanyContactFinder.Leads.Pipeline.run(lookup.id)

    {:ok, view, _html} = live(conn, ~p"/lookups/#{lookup}")
    refute has_element?(view, "#brief-fit")

    view |> form("#bucket-form", bucket_id: bucket.id) |> render_change()
    await_done(lookup.id)

    assert has_element?(view, "#brief-fit", "Strong fit")
    assert has_element?(view, "#brief-pitch")
    assert Repo.get!(Lookup, lookup.id).bucket_id == bucket.id
  end

  test "finding companies online and adding the picked ones", %{conn: conn} do
    stub_discovery()
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    {:ok, view, _html} = live(conn, ~p"/buckets/#{bucket}")

    view |> element("#discover-companies") |> render_click()
    assert render_async(view) =~ "Companies found online"
    assert has_element?(view, "#discovery-form", "Bidii Freight")
    refute has_element?(view, "#discovery-form", "Invented Haulage")

    # Adding runs the normal lookup pipeline, so stub it for the picked company.
    stub_all()

    view
    |> form("#discovery-form", pick: %{names: ["Bidii Freight"]})
    |> render_submit()

    assert [%Lookup{company_name: "Bidii Freight"} = lookup] =
             Repo.all(from l in Lookup, where: l.bucket_id == ^bucket.id)

    await_done(lookup.id)
    refute has_element?(view, "#discovery-form", "Bidii Freight")
    assert has_element?(view, "#discovery-form", "Chui Couriers")
  end

  test "shows why online search failed", %{conn: conn} do
    stub_serper_error(401)
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    {:ok, view, _html} = live(conn, ~p"/buckets/#{bucket}")

    view |> element("#discover-companies") |> render_click()
    assert render_async(view) =~ "Serper rejected the API key"
  end
end
