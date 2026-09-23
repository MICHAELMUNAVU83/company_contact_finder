defmodule CompanyContactFinderWeb.ExportController do
  use CompanyContactFinderWeb, :controller

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.CSVExport

  def index(conn, _params) do
    send_csv(conn, "gs1-kenya-leads-#{Date.utc_today()}.csv", Leads.list_lookups_for_export())
  end

  def show(conn, %{"id" => id}) do
    lookup = Leads.get_lookup!(id)
    send_csv(conn, "#{slug(lookup.company_name)}-lead.csv", [lookup])
  end

  def bucket(conn, %{"id" => id}) do
    bucket = Leads.get_bucket!(id)
    lookups = Leads.list_lookups_for_export(bucket_id: bucket.id)
    send_csv(conn, "#{slug(bucket.name)}-leads-#{Date.utc_today()}.csv", lookups)
  end

  defp send_csv(conn, filename, lookups) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, CSVExport.to_csv(lookups))
  end

  defp slug(name) do
    case name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-") do
      "" -> "leads"
      slug -> String.slice(slug, 0, 60)
    end
  end
end
