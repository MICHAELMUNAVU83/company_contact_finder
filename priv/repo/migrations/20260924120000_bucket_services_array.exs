defmodule CompanyContactFinder.Repo.Migrations.BucketServicesArray do
  use Ecto.Migration

  def up do
    alter table(:buckets) do
      add :services, {:array, :string}, null: false, default: []
    end

    execute "UPDATE buckets SET services = ARRAY[service]"

    alter table(:buckets) do
      remove :service
    end
  end

  def down do
    alter table(:buckets) do
      add :service, :string
    end

    execute "UPDATE buckets SET service = COALESCE(array_to_string(services, ', '), '')"
    execute "ALTER TABLE buckets ALTER COLUMN service SET NOT NULL"

    alter table(:buckets) do
      remove :services
    end
  end
end
