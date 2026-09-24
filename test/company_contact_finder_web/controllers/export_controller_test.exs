defmodule CompanyContactFinderWeb.ExportControllerTest do
  use CompanyContactFinderWeb.ConnCase, async: true

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Lookup
  alias CompanyContactFinder.Repo

  setup do
    lookup =
      Repo.insert!(%Lookup{
        company_name: "Acme Logistics",
        status: :done,
        website_url: "https://acme.com"
      })

    Leads.add_contacts(lookup, [
      %{type: :email, value: "info@acme.com", source_url: "https://acme.com"}
    ])

    Leads.save_brief(lookup, %{status: :done, lead_score: 70})
    %{lookup: lookup}
  end

  test "exports all lookups", %{conn: conn} do
    conn = get(conn, ~p"/export.csv")

    assert response_content_type(conn, :csv)
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    assert response(conn, 200) =~ "Acme Logistics,,https://acme.com,done,70"
  end

  test "exports a bucket's leads", %{conn: conn, lookup: lookup} do
    {:ok, bucket} =
      Leads.create_bucket(%{
        name: "Food makers",
        target_description: "Food",
        services: ["Barcodes"]
      })

    {:ok, _} = Leads.assign_bucket(lookup, bucket.id)
    conn = get(conn, ~p"/buckets/#{bucket}/export.csv")

    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "food-makers-leads-"
    assert response(conn, 200) =~ "Acme Logistics,Food makers,"
  end

  test "exports one lookup", %{conn: conn, lookup: lookup} do
    conn = get(conn, ~p"/lookups/#{lookup}/export.csv")

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="acme-logistics-lead.csv")
           ]

    assert response(conn, 200) =~ "info@acme.com"
  end
end
