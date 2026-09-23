defmodule CompanyContactFinder.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts) do
      add :lookup_id, references(:lookups, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :value, :string, null: false
      add :source_url, :text
      add :role, :string
      add :quality, :string
      add :ai_note, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:contacts, [:lookup_id, :type, :value])
  end
end
