defmodule CompanyContactFinder.Repo.Migrations.AddCampaignEmails do
  use Ecto.Migration

  def change do
    alter table(:buckets) do
      add :email_mode, :string, null: false, default: "static"
      add :email_subject, :text
      add :email_template, :text
      add :email_prompt, :text
    end

    create table(:outreach_messages) do
      add :bucket_id, references(:buckets, on_delete: :delete_all), null: false
      add :lookup_id, references(:lookups, on_delete: :delete_all), null: false
      add :to, :string, null: false
      add :cc, :string
      add :subject, :text, null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:outreach_messages, [:bucket_id, :lookup_id])
  end
end
