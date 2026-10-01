defmodule CompanyContactFinder.Leads.Bucket do
  @moduledoc """
  A lead bucket: the kind of companies we're looking for and the catalog
  products we will offer them. Lookups in a bucket are scored against it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CompanyContactFinder.Catalog.Product

  @sizes ~w(small medium large)
  @breadths ~w(narrow wide)
  @flows ~w(acquire upsell)
  @email_modes ~w(static dynamic)

  schema "buckets" do
    field :name, :string
    field :target_description, :string
    field :industries, {:array, :string}, default: []
    field :locations, {:array, :string}, default: []
    field :company_sizes, {:array, :string}, default: []
    field :services, {:array, :string}, default: []
    field :service_details, :string
    field :disqualifiers, :string
    field :breadth, :string, default: "narrow"
    field :flow, :string, default: "acquire"
    field :max_companies, :integer, default: 200
    field :email_mode, :string, default: "static"
    field :email_subject, :string
    field :email_template, :string
    field :email_prompt, :string
    field :criteria_changed_at, :utc_datetime
    field :product_ids, {:array, :integer}, virtual: true, default: []

    field :lead_count, :integer, virtual: true
    field :strong_count, :integer, virtual: true
    field :avg_score, :float, virtual: true

    many_to_many :products, Product, join_through: "bucket_products", on_replace: :delete
    has_many :lookups, CompanyContactFinder.Leads.Lookup

    timestamps(type: :utc_datetime)
  end

  def sizes, do: @sizes
  def breadths, do: @breadths
  def flows, do: @flows
  def email_modes, do: @email_modes

  @campaign [:email_mode, :email_subject, :email_template, :email_prompt]

  def campaign_changeset(bucket, attrs) do
    bucket
    |> cast(attrs, @campaign)
    |> validate_inclusion(:email_mode, @email_modes)
    |> validate_length(:email_subject, max: 200)
    |> validate_length(:email_template, max: 8000)
    |> validate_length(:email_prompt, max: 4000)
  end

  # Changing any of these makes existing scores out of date.
  @criteria [
    :target_description,
    :industries,
    :locations,
    :company_sizes,
    :services,
    :service_details,
    :disqualifiers,
    :product_ids,
    :flow
  ]

  def changeset(bucket, attrs) do
    attrs = split_lists(attrs)

    bucket
    |> cast(attrs, [:name, :breadth, :max_companies, :product_ids | @criteria])
    |> update_change(:company_sizes, &Enum.reject(&1, fn size -> size == "" end))
    |> update_change(:product_ids, &normalize_ids/1)
    |> validate_required([:name, :target_description])
    |> validate_products()
    |> validate_inclusion(:breadth, @breadths)
    |> validate_inclusion(:flow, @flows)
    |> validate_number(:max_companies, greater_than: 0, less_than_or_equal_to: 500)
    |> validate_length(:name, max: 120)
    |> validate_length(:target_description, max: 2000)
    |> validate_length(:service_details, max: 2000)
    |> validate_length(:disqualifiers, max: 2000)
    |> validate_subset(:company_sizes, @sizes)
    |> touch_criteria()
  end

  defp normalize_ids(nil), do: []

  defp normalize_ids(ids) do
    ids
    |> Enum.map(fn
      id when is_integer(id) ->
        id

      id when is_binary(id) ->
        case Integer.parse(id) do
          {int, ""} -> int
          _ -> nil
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp validate_products(changeset) do
    ids = get_change(changeset, :product_ids)

    cond do
      changeset.data.id && is_nil(ids) ->
        changeset

      ids in [nil, []] ->
        add_error(changeset, :product_ids, "pick at least one product")

      true ->
        changeset
    end
  end

  defp touch_criteria(changeset) do
    if Enum.any?(@criteria, &Map.has_key?(changeset.changes, &1)) or is_nil(changeset.data.id),
      do: put_change(changeset, :criteria_changed_at, DateTime.utc_now(:second)),
      else: changeset
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
