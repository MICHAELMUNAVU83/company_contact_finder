defmodule CompanyContactFinder.Repo.Migrations.AddBucketEmailFooters do
  use Ecto.Migration

  def change do
    alter table(:buckets) do
      add :email_footer, :text
      add :from_name, :string
      add :from_email, :string
    end
  end
end
