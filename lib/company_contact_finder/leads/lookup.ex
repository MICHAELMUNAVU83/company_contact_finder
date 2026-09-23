defmodule CompanyContactFinder.Leads.Lookup do
  @moduledoc """
  One search for one company: the resolved website, crawl status and the
  scraped page text that feeds the AI brief.

  `source` is `:website` when `website_url` is the company's own site (crawled
  from its root), or `:listing` when it is the company's page on a directory
  such as Yellow Pages (only that page is fetched).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CompanyContactFinder.Leads.{Bucket, CompanyBrief, Contact}

  alias CompanyContactFinder.Scraper.UrlGuard
  alias CompanyContactFinder.Search.WebsiteResolver

  @statuses [:pending, :searching, :crawling, :analysing, :done, :failed]
  @sources [:website, :listing]

  schema "lookups" do
    field :company_name, :string
    field :query, :string
    field :website_url, :string
    field :website_overridden, :boolean, default: false
    field :source, Ecto.Enum, values: @sources, default: :website
    field :candidates, {:array, :map}, default: []
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :error, :string
    field :scraped_text, :string
    field :pages_crawled, :integer, default: 0
    field :contact_count, :integer, virtual: true

    belongs_to :bucket, Bucket
    has_many :contacts, Contact
    has_one :brief, CompanyBrief

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc "Changeset for user input when starting a lookup."
  def create_changeset(lookup, attrs) do
    lookup
    |> cast(attrs, [:company_name, :bucket_id])
    |> update_change(:company_name, &squish/1)
    |> validate_required([:company_name])
    |> validate_length(:company_name, min: 2, max: 200)
    |> assoc_constraint(:bucket)
  end

  @doc "Changeset for moving a lookup to another bucket (or none)."
  def bucket_changeset(lookup, attrs) do
    lookup
    |> cast(attrs, [:bucket_id])
    |> assoc_constraint(:bucket)
  end

  @doc "Changeset for a user-supplied website that replaces the resolved one."
  def website_changeset(lookup, attrs) do
    lookup
    |> cast(attrs, [:website_url])
    |> update_change(:website_url, &String.trim/1)
    |> validate_required([:website_url])
    |> validate_length(:website_url, max: 2000)
    |> normalize_website()
    |> put_change(:website_overridden, true)
  end

  @doc "Changeset used by the pipeline to record progress."
  def progress_changeset(lookup, attrs) do
    cast(lookup, attrs, [
      :query,
      :website_url,
      :source,
      :candidates,
      :status,
      :error,
      :scraped_text,
      :pages_crawled
    ])
  end

  # A company site is crawled from its root. A page on a directory or social
  # site is kept as-is and treated as the company's listing.
  defp normalize_website(changeset) do
    with url when is_binary(url) <- get_change(changeset, :website_url),
         {:ok, uri} <- UrlGuard.parse(url) do
      cond do
        not WebsiteResolver.blocked_host?(uri.host) ->
          {:ok, root} = UrlGuard.normalize_root(url)
          changeset |> put_change(:website_url, root) |> put_change(:source, :website)

        uri.path in [nil, "", "/"] ->
          add_error(
            changeset,
            :website_url,
            "is a directory or social site, paste the company's own page on it"
          )

        true ->
          changeset
          |> put_change(:website_url, URI.to_string(%{uri | fragment: nil}))
          |> put_change(:source, :listing)
      end
    else
      nil -> changeset
      {:error, _} -> add_error(changeset, :website_url, "must be a public http(s) website")
    end
  end

  defp squish(value), do: value |> String.split() |> Enum.join(" ")
end
