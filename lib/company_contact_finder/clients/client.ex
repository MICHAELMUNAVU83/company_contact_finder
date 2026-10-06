defmodule CompanyContactFinder.Clients.Client do
  @moduledoc """
  A company that is already a GS1 Kenya client. Uploaded by the team and
  used by upsell buckets. Fresh-acquire search leaves these names out.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "clients" do
    field :company_name, :string
    field :name_key, :string
    field :email, :string
    field :phone, :string
    field :website_url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(client, attrs) do
    client
    |> cast(attrs, [:company_name, :email, :phone, :website_url])
    |> update_change(:company_name, &squish/1)
    |> update_change(:email, &normalize_email/1)
    |> update_change(:phone, &clean_phone/1)
    |> update_change(:website_url, &trim_blank/1)
    |> put_name_key()
    |> validate_required([:company_name, :name_key])
    |> validate_length(:company_name, min: 2, max: 200)
    |> validate_length(:email, max: 200)
    |> validate_length(:phone, max: 40)
    |> validate_length(:website_url, max: 2000)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be an email")
    |> unique_constraint(:name_key)
  end

  def name_key(name) when is_binary(name) do
    name |> squish() |> String.downcase()
  end

  def name_key(_), do: nil

  defp put_name_key(changeset) do
    case get_field(changeset, :company_name) do
      name when is_binary(name) and name != "" ->
        put_change(changeset, :name_key, name_key(name))

      _ ->
        changeset
    end
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) do
    email = email |> String.trim() |> String.downcase()
    if email == "", do: nil, else: email
  end

  defp clean_phone(nil), do: nil

  defp clean_phone(value) do
    value = value |> squish() |> String.slice(0, 40)
    if value == "", do: nil, else: value
  end

  defp trim_blank(nil), do: nil

  defp trim_blank(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp squish(nil), do: nil
  defp squish(value), do: value |> String.split() |> Enum.join(" ")
end
