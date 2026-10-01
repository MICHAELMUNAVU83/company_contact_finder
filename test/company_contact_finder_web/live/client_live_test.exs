defmodule CompanyContactFinderWeb.ClientLiveTest do
  use CompanyContactFinderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CompanyContactFinder.Clients

  test "uploading and removing a client", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/clients")
    assert has_element?(view, "#clients-empty")
    assert has_element?(view, "#nav-clients")

    csv = "company,email,website\nBidii Foods,hello@bidii.co.ke,bidii.co.ke\n"

    upload =
      file_input(view, "#client-upload", :clients, [
        %{name: "clients.csv", content: csv, type: "text/csv"}
      ])

    assert render_upload(upload, "clients.csv")
    view |> form("#client-upload") |> render_submit()

    assert Clients.count_clients() == 1
    assert has_element?(view, "#clients", "Bidii Foods")
    assert has_element?(view, "#clients", "hello@bidii.co.ke")
    refute has_element?(view, "#clients-empty")

    [client] = Clients.list_clients()
    view |> element("#delete-client-#{client.id}") |> render_click()

    assert Clients.count_clients() == 0
    assert has_element?(view, "#clients-empty")
  end
end
