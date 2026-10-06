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

  test "create, update, and delete a product" do
    attrs = %{
      name: "  Trace  ",
      audience: " Warehouses ",
      not_for: " Offices ",
      proof_points: [" Scan a tag ", ""],
      owner_email: " Owner@Example.com "
    }

    assert {:error, changeset} = Catalog.create_product(attrs)
    assert "needs exactly two proof points" in errors_on(changeset).proof_points

    assert {:ok, product} =
             Catalog.create_product(%{
               attrs
               | proof_points: [" Scan a tag ", " See its location "]
             })

    assert product.name == "Trace"
    assert product.audience == "Warehouses"
    assert product.not_for == "Offices"
    assert product.proof_points == ["Scan a tag", "See its location"]
    assert product.owner_email == "owner@example.com"

    assert {:ok, product} = Catalog.update_product(product, %{name: "Traceability"})
    assert product.name == "Traceability"

    assert {:ok, _product} = Catalog.delete_product(product)
    assert Catalog.list_products() == []
  end
end
