defmodule CompanyContactFinder.Repo.Migrations.AddBriefProduct do
  use Ecto.Migration

  def change do
    alter table(:company_briefs) do
      add :recommended_product_id, references(:products, on_delete: :nilify_all)
      add :product_reason, :text
      add :owner_email, :string
    end
  end
end
