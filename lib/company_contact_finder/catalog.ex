defmodule CompanyContactFinder.Catalog do
  @moduledoc """
  Products the lead finder can pitch.
  """

  import Ecto.Query

  alias CompanyContactFinder.Catalog.Product
  alias CompanyContactFinder.Repo

  @doc "Products in name order."
  def list_products do
    Repo.all(from p in Product, order_by: p.name)
  end

  def get_product!(id), do: Repo.get!(Product, id)

  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  def create_product(attrs) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  def delete_product(%Product{} = product) do
    Repo.delete(product)
  end

  @doc "Inserts the starter catalog. Existing names are left as they are."
  def seed_products do
    Enum.each(starter_products(), fn attrs ->
      %Product{}
      |> Product.changeset(attrs)
      |> Repo.insert!(on_conflict: :nothing, conflict_target: :name)
    end)

    :ok
  end

  @doc false
  def starter_products do
    [
      %{
        name: "GS1 barcodes",
        audience: "Manufacturers, exporters, and retailers that are not GS1 members",
        not_for: "Companies that already have a GS1 company prefix",
        proof_points: [
          "GTINs for products sold through retailers or export",
          "Onboarding for a company prefix and the first product numbers"
        ],
        owner_email: "barcodes-owner@example.com"
      },
      %{
        name: "Hakikisha",
        audience: "Brands and factories that need GTIN checks and barcode print grades",
        not_for: "Businesses with no packaged products",
        proof_points: [
          "Verify a GTIN against a registry",
          "Grade barcode print quality from a photo"
        ],
        owner_email: "hakikisha-owner@example.com"
      },
      %{
        name: "Fixed Asset",
        audience: "Hospitals, factories, and warehouses that tag equipment",
        not_for: "Teams with no physical assets to track",
        proof_points: [
          "Scan a tag and open the asset record",
          "Register name, location, custodian, and condition"
        ],
        owner_email: "fixed-asset-owner@example.com"
      },
      %{
        name: "Thamani Dawa",
        audience: "Independent pharmacies and diagnostic labs",
        not_for: "Retailers that do not handle medicine or lab stock",
        proof_points: [
          "Pharmacy stock, prescriptions, and batch traceability",
          "Lab orders, result verification, and reagent stock"
        ],
        owner_email: "thamani-dawa-owner@example.com"
      },
      %{
        name: "Sokochat",
        audience: "Businesses that already sell on WhatsApp and have a catalog or API",
        not_for: "Companies with no buyer conversations on WhatsApp",
        proof_points: [
          "Answers price and availability questions from live catalog data",
          "Test replies in a browser before connecting WhatsApp"
        ],
        owner_email: "sokochat-owner@example.com"
      },
      %{
        name: "Wasomi",
        audience: "Teams selling a paid online course",
        not_for: "Organisations that do not deliver training",
        proof_points: [
          "Learners pay, watch lectures, and receive a certificate",
          "Admins upload courses and track payments"
        ],
        owner_email: "wasomi-owner@example.com"
      },
      %{
        name: "Construct",
        audience: "Contractors running projects, crews, and materials",
        not_for: "Businesses outside construction",
        proof_points: [
          "Projects, tasks, workers, and time on one site",
          "Materials, purchase orders, and project costs"
        ],
        owner_email: "construct-owner@example.com"
      }
    ]
  end
end
