defmodule CompanyContactFinder.Outreach.Message do
  @moduledoc """
  One email that was actually sent for a lead. Drafts are not stored here.
  """
  use Ecto.Schema

  schema "outreach_messages" do
    field :to, :string
    field :cc, :string
    field :subject, :string
    field :body, :string

    belongs_to :bucket, CompanyContactFinder.Leads.Bucket
    belongs_to :lookup, CompanyContactFinder.Leads.Lookup

    timestamps(type: :utc_datetime)
  end
end
