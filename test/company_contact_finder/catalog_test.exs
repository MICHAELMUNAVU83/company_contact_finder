defmodule CompanyContactFinder.CatalogTest do
  use CompanyContactFinder.DataCase, async: true

  alias CompanyContactFinder.Catalog
  alias CompanyContactFinder.Catalog.Product

  test "seed_products inserts the starter catalog once" do
    assert :ok = Catalog.seed_products()
    assert :ok = Catalog.seed_products()

    products = Catalog.list_products()
    assert length(products) == 7
    assert Enum.map(products, & &1.name) == Enum.sort(Enum.map(products, & &1.name))

    barcodes = Enum.find(products, &(&1.name == "GS1 barcodes"))
    assert length(barcodes.proof_points) == 2
    assert barcodes.owner_email == "barcodes-owner@example.com"
  end

  test "a product needs two proof points and an email" do
    changeset =
      Product.changeset(%Product{}, %{
        name: "Example",
        audience: "Someone",
        not_for: "Someone else",
        proof_points: ["Only one"],
        owner_email: "not-an-email"
      })

    refute changeset.valid?
    assert "must be an email" in errors_on(changeset).owner_email
    assert errors_on(changeset).proof_points != []
  end
end
