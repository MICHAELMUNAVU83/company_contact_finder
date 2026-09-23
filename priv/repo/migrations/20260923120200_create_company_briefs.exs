defmodule CompanyContactFinder.Repo.Migrations.CreateCompanyBriefs do
  use Ecto.Migration

  def change do
    create table(:company_briefs) do
      add :lookup_id, references(:lookups, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :summary, :text
      add :industry, :string
      add :products_services, {:array, :string}, null: false, default: []
      add :locations, {:array, :string}, null: false, default: []
      add :company_size_hint, :string
      add :target_customers, :text
      add :best_contact, :string
      add :lead_score, :integer
      add :lead_score_reason, :text
      add :outreach_angle, :text
      add :raw_response, :map
      add :model, :string
      add :prompt_tokens, :integer
      add :completion_tokens, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:company_briefs, [:lookup_id])
    create index(:company_briefs, [:lead_score])
  end
end
