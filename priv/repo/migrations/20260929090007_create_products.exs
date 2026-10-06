defmodule CompanyContactFinder.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :name, :string, null: false
      add :audience, :text, null: false
      add :not_for, :text, null: false
      add :proof_points, {:array, :string}, null: false, default: []
      add :owner_email, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:products, [:name])
  end
end
