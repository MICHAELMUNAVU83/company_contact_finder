defmodule CompanyContactFinder.Repo.Migrations.AddClientsAndBucketFlow do
  use Ecto.Migration

  def change do
    alter table(:buckets) do
      add :flow, :string, null: false, default: "acquire"
    end

    create table(:clients) do
      add :company_name, :string, null: false
      add :name_key, :string, null: false
      add :email, :string
      add :phone, :string
      add :website_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:clients, [:name_key])
  end
end
