defmodule CompanyContactFinder.Leads.CompanyBrief do
  @moduledoc """
  AI-generated brief for a lookup. Stored separately so it can fail and be
  retried without affecting the scraped contacts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :done, :failed]
  @sizes ~w(small medium large unknown)
  @fits ~w(strong partial weak unknown)

  schema "company_briefs" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :error, :string
    field :summary, :string
    field :industry, :string
    field :products_services, {:array, :string}, default: []
    field :locations, {:array, :string}, default: []
    field :company_size_hint, :string
    field :target_customers, :string
    field :best_contact, :string
    field :lead_score, :integer
    field :lead_score_reason, :string
    field :outreach_angle, :string
    field :fit, :string
    field :fit_reason, :string
    field :pitch, :string
    field :scored_bucket_id, :integer
    field :scored_at, :utc_datetime
    field :raw_response, :map
    field :model, :string
    field :prompt_tokens, :integer
    field :completion_tokens, :integer

    belongs_to :lookup, CompanyContactFinder.Leads.Lookup

    timestamps(type: :utc_datetime)
  end

  @fields [
    :status,
    :error,
    :summary,
    :industry,
    :products_services,
    :locations,
    :company_size_hint,
    :target_customers,
    :best_contact,
    :lead_score,
    :lead_score_reason,
    :outreach_angle,
    :fit,
    :fit_reason,
    :pitch,
    :scored_bucket_id,
    :scored_at,
    :raw_response,
    :model,
    :prompt_tokens,
    :completion_tokens
  ]

  def changeset(brief, attrs) do
    brief
    |> cast(attrs, @fields)
    |> validate_required([:status])
    |> validate_number(:lead_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:company_size_hint, @sizes)
    |> validate_inclusion(:fit, @fits)
  end
end
