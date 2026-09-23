defmodule CompanyContactFinder.Leads.Contact do
  @moduledoc """
  A piece of public contact info found on a company website, optionally
  annotated by the AI analysis.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @types [:email, :phone, :social]
  @roles ~w(general sales support hr person other)
  @qualities ~w(high medium low)

  schema "contacts" do
    field :type, Ecto.Enum, values: @types
    field :value, :string
    field :source_url, :string
    field :role, :string
    field :quality, :string
    field :ai_note, :string

    belongs_to :lookup, CompanyContactFinder.Leads.Lookup

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def roles, do: @roles
  def qualities, do: @qualities

  def analysis_changeset(contact, attrs) do
    contact
    |> cast(attrs, [:role, :quality, :ai_note])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:quality, @qualities)
  end
end
