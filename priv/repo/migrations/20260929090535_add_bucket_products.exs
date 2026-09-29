defmodule CompanyContactFinder.Repo.Migrations.AddBucketProducts do
  use Ecto.Migration

  def change do
    alter table(:buckets) do
      add :breadth, :string, null: false, default: "narrow"
      add :max_companies, :integer, null: false, default: 25
    end

    create table(:bucket_products, primary_key: false) do
      add :bucket_id, references(:buckets, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
    end

    create unique_index(:bucket_products, [:bucket_id, :product_id])
  end
end
