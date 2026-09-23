defmodule CompanyContactFinder.Repo.Migrations.CreateLookups do
  use Ecto.Migration

  def change do
    create table(:lookups) do
      add :company_name, :string, null: false
      add :query, :string
      add :website_url, :string
      add :website_overridden, :boolean, null: false, default: false
      add :candidates, {:array, :map}, null: false, default: []
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :scraped_text, :text
      add :pages_crawled, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:lookups, [:inserted_at])
    create index(:lookups, [:status])
  end
end
