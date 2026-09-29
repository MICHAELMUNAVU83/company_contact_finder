defmodule CompanyContactFinder.Catalog.Product do
  @moduledoc """
  A product we can offer a lead. The brief and the email drafter read this
  card instead of a free-text service name.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string
    field :audience, :string
    field :not_for, :string
    field :proof_points, {:array, :string}, default: []
    field :owner_email, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :audience, :not_for, :proof_points, :owner_email])
    |> update_change(:name, &String.trim/1)
    |> update_change(:owner_email, &normalize_email/1)
    |> validate_required([:name, :audience, :not_for, :owner_email])
    |> validate_length(:name, max: 120)
    |> validate_length(:proof_points, min: 2, max: 2)
    |> validate_format(:owner_email, ~r/^[^\s]+@[^\s]+$/, message: "must be an email")
    |> unique_constraint(:name)
  end

  defp normalize_email(nil), do: nil
  defp normalize_email(email), do: email |> String.trim() |> String.downcase()
end
