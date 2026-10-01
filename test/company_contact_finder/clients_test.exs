defmodule CompanyContactFinder.ClientsTest do
  use CompanyContactFinder.DataCase, async: true

  alias CompanyContactFinder.Clients
  alias CompanyContactFinder.Clients.CSV

  test "parses a header row, quoted commas, and a bare name list" do
    csv = """
    company,email,phone,website
    "Acme, Ltd",Sales@Acme.co.ke,+254700000000,acme.co.ke
    ,
    Bidii Foods,not-an-email,,
    """

    assert [
             %{
               "company_name" => "Acme, Ltd",
               "email" => "Sales@Acme.co.ke",
               "website_url" => "acme.co.ke"
             },
             %{"company_name" => "Bidii Foods", "email" => "not-an-email"}
           ] = CSV.parse(csv)

    assert CSV.parse("Globex Kenya\nAcme Foods\n") == [
             %{"company_name" => "Globex Kenya"},
             %{"company_name" => "Acme Foods"}
           ]
  end

  test "imports clients and updates them on a second upload" do
    assert %{inserted: 2, updated: 0, skipped: 1, truncated: false} =
             Clients.import_csv("""
             company,email,phone,website
             Acme Foods,sales@acme.co.ke,+254700000000,acme.co.ke
             Bidii Foods,not-an-email,,
             A
             """)

    [acme, bidii] = Clients.list_clients()
    assert acme.company_name == "Acme Foods"
    assert acme.email == "sales@acme.co.ke"
    assert acme.website_url == "https://acme.co.ke"
    assert bidii.email == nil

    assert %{inserted: 0, updated: 1, skipped: 0, truncated: false} =
             Clients.import_csv("company,email\nAcme Foods,hello@acme.co.ke\n")

    [acme] = Clients.list_clients() |> Enum.filter(&(&1.company_name == "Acme Foods"))
    assert acme.email == "hello@acme.co.ke"
    assert acme.website_url == "https://acme.co.ke"
  end
end
