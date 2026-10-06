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
    |> update_change(:name, &trim/1)
    |> update_change(:audience, &trim/1)
    |> update_change(:not_for, &trim/1)
    |> update_change(:owner_email, &normalize_email/1)
    |> update_change(:proof_points, &normalize_proof_points/1)
    |> validate_required([:name, :audience, :not_for, :owner_email])
    |> validate_length(:name, max: 120)
    |> validate_proof_points()
    |> validate_format(:owner_email, ~r/^[^\s]+@[^\s]+$/, message: "must be an email")
    |> unique_constraint(:name)
  end

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  defp normalize_email(nil), do: nil
  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

  defp normalize_proof_points(points) do
    points
    |> List.wrap()
    |> Enum.map(fn
      point when is_binary(point) -> String.trim(point)
      point -> point |> to_string() |> String.trim()
    end)
  end

  defp validate_proof_points(changeset) do
    points = get_field(changeset, :proof_points) || []
    filled = Enum.count(points, &(&1 != ""))

    if length(points) == 2 and filled == 2 do
      changeset
    else
      add_error(changeset, :proof_points, "needs exactly two proof points")
    end
  end
end
