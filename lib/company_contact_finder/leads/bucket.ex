defmodule CompanyContactFinder.Leads.Bucket do
  @moduledoc """
  A lead bucket: the kind of companies we're looking for and the GS1 Kenya
  service we want to offer them. Lookups in a bucket are scored against it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @sizes ~w(small medium large)

  @services [
    "GS1 barcodes (GTINs) for products",
    "Global Location Numbers (GLNs)",
    "SSCC logistics labels",
    "Traceability solutions",
    "Barcode verification & quality testing",
    "GS1 standards training",
    "Product data management"
  ]

  schema "buckets" do
    field :name, :string
    field :target_description, :string
    field :industries, {:array, :string}, default: []
    field :locations, {:array, :string}, default: []
    field :company_sizes, {:array, :string}, default: []
    field :services, {:array, :string}, default: []
    field :service_details, :string
    field :disqualifiers, :string
    field :criteria_changed_at, :utc_datetime

    field :lead_count, :integer, virtual: true
    field :strong_count, :integer, virtual: true
    field :avg_score, :float, virtual: true

    has_many :lookups, CompanyContactFinder.Leads.Lookup

    timestamps(type: :utc_datetime)
  end

  def sizes, do: @sizes
  def services, do: @services

  # Changing any of these makes existing scores out of date.
  @criteria [
    :target_description,
    :industries,
    :locations,
    :company_sizes,
    :services,
    :service_details,
    :disqualifiers
  ]

  def changeset(bucket, attrs) do
    attrs = split_lists(attrs)

    bucket
    |> cast(attrs, [:name | @criteria])
    |> update_change(:company_sizes, &Enum.reject(&1, fn size -> size == "" end))
    |> validate_required([:name, :target_description])
    |> validate_length(:services, min: 1, message: "pick at least one service")
    |> validate_change(:services, &validate_service_lengths/2)
    |> validate_length(:name, max: 120)
    |> validate_length(:target_description, max: 2000)
    |> validate_length(:service_details, max: 2000)
    |> validate_length(:disqualifiers, max: 2000)
    |> validate_subset(:company_sizes, @sizes)
    |> touch_criteria()
  end

  defp touch_criteria(changeset) do
    if Enum.any?(@criteria, &Map.has_key?(changeset.changes, &1)) or is_nil(changeset.data.id),
      do: put_change(changeset, :criteria_changed_at, DateTime.utc_now(:second)),
      else: changeset
  end

  defp validate_service_lengths(:services, services) do
    if Enum.any?(services, &(String.length(&1) > 200)),
      do: [services: "each service must be at most 200 characters"],
      else: []
  end

  # Industries, locations and services are typed as comma-separated text in the form.
  defp split_lists(attrs) do
    Enum.reduce(["industries", "locations", "services"], attrs, fn key, attrs ->
      case attrs do
        %{^key => value} when is_binary(value) ->
          items =
            value
            |> String.split([",", "\n"])
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          Map.put(attrs, key, Enum.uniq(items))

        _ ->
          attrs
      end
    end)
  end
end
