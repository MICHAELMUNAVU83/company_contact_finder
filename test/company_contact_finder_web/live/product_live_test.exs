defmodule CompanyContactFinderWeb.ProductLiveTest do
  use CompanyContactFinderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CompanyContactFinder.Catalog

  @valid %{
    name: "Trace",
    audience: "Warehouses that tag pallets",
    not_for: "Teams with nothing to scan",
    proof_points: ["Scan a tag", "Open the pallet record"],
    owner_email: "trace@example.com"
  }

  test "index shows the empty state and product cards", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/products")
    assert has_element?(view, "#products-empty")
    assert has_element?(view, "#nav-products")

    {:ok, product} = Catalog.create_product(@valid)
    {:ok, view, _html} = live(conn, ~p"/products")
    assert has_element?(view, "#products-#{product.id}", "Trace")
    assert has_element?(view, "#products-#{product.id}", "trace@example.com")
  end

  test "loading the starter catalog", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/products")

    view |> element("#load-starter-products") |> render_click()

    assert length(Catalog.list_products()) == 7
    assert has_element?(view, "#products", "GS1 barcodes")
  end

  test "creating a product", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/products/new")

    view |> form("#product-form", product: %{name: ""}) |> render_change()
    assert has_element?(view, "#product-form", "can't be blank")

    view
    |> form("#product-form", product: Map.put(@valid, :proof_points, ["Only one", ""]))
    |> render_submit()

    assert has_element?(view, "#proof-points-error", "needs exactly two proof points")

    view |> form("#product-form", product: @valid) |> render_submit()

    assert_redirect(view, ~p"/products")
    assert Enum.map(Catalog.list_products(), & &1.name) == ["Trace"]
  end

  test "editing a product", %{conn: conn} do
    {:ok, product} = Catalog.create_product(@valid)
    {:ok, view, _html} = live(conn, ~p"/products/#{product}/edit")

    view |> form("#product-form", product: %{name: "Renamed"}) |> render_submit()

    assert Catalog.get_product!(product.id).name == "Renamed"
    assert_redirect(view, ~p"/products")
  end

  test "deleting a product", %{conn: conn} do
    {:ok, product} = Catalog.create_product(@valid)
    {:ok, view, _html} = live(conn, ~p"/products")

    view |> element("#delete-product-#{product.id}") |> render_click()

    assert Catalog.list_products() == []
    refute has_element?(view, "#products-#{product.id}")
  end
end
