defmodule CompanyContactFinder.Repo.Migrations.AddSourceToLookups do
  use Ecto.Migration

  def change do
    alter table(:lookups) do
      add :source, :string, null: false, default: "website"
    end
  end
end
