defmodule CompanyContactFinder.Repo.Migrations.CreateBuckets do
  use Ecto.Migration

  def change do
    create table(:buckets) do
      add :name, :string, null: false
      add :target_description, :text, null: false
      add :industries, {:array, :string}, null: false, default: []
      add :locations, {:array, :string}, null: false, default: []
      add :company_sizes, {:array, :string}, null: false, default: []
      add :service, :string, null: false
      add :service_details, :text
      add :disqualifiers, :text
      add :criteria_changed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    alter table(:lookups) do
      add :bucket_id, references(:buckets, on_delete: :nilify_all)
    end

    create index(:lookups, [:bucket_id])

    alter table(:company_briefs) do
      add :fit, :string
      add :fit_reason, :text
      add :pitch, :text
      add :scored_bucket_id, :integer
      add :scored_at, :utc_datetime
    end
  end
end
