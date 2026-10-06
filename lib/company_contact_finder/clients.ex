defmodule CompanyContactFinder.Clients do
  @moduledoc """
  The uploaded list of companies that are already GS1 Kenya clients.
  """

  import Ecto.Query

  alias CompanyContactFinder.Clients.Client
  alias CompanyContactFinder.Clients.CSV
  alias CompanyContactFinder.Leads.Lookup
  alias CompanyContactFinder.Repo

  @max_rows 5_000
  @page_size 100

  def list_clients(opts \\ []) do
    limit = Keyword.get(opts, :limit, @page_size)

    Repo.all(from c in Client, order_by: [asc: c.company_name, asc: c.id], limit: ^limit)
  end

  def count_clients, do: Repo.aggregate(Client, :count)

  def company_names do
    Repo.all(from c in Client, select: c.company_name)
  end

  @doc "Clients in `ids`, in name order."
  def list_clients_by_ids(ids) when is_list(ids) do
    Repo.all(from c in Client, where: c.id in ^ids, order_by: c.company_name)
  end

  def delete_client(%Client{} = client), do: Repo.delete(client)

  @doc """
  Clients whose company is not already a lead in the bucket.
  """
  def available_for_bucket(bucket_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 40)

    bucket_id
    |> available_query()
    |> limit(^limit)
    |> Repo.all()
  end

  def available_ids(bucket_id, limit) do
    bucket_id
    |> available_query()
    |> limit(^limit)
    |> select([c], c.id)
    |> Repo.all()
  end

  def available_count(bucket_id) do
    bucket_id
    |> available_query()
    |> Repo.aggregate(:count)
  end

  defp available_query(bucket_id) do
    from c in Client,
      as: :client,
      where:
        not exists(
          from l in Lookup,
            where:
              l.bucket_id == ^bucket_id and
                fragment(
                  "lower(regexp_replace(btrim(?), '\\s+', ' ', 'g'))",
                  l.company_name
                ) == parent_as(:client).name_key,
            select: 1
        ),
      order_by: [asc: c.company_name, asc: c.id]
  end

  @doc """
  Inserts or updates clients from CSV text.

  Returns `%{inserted: n, updated: n, skipped: n, truncated: boolean}`.
  A row is skipped when the company name is missing or invalid. Uploading
  the same company again updates the email, phone and website when those
  cells are filled in.
  """
  def import_csv(text) when is_binary(text) do
    rows = CSV.parse(text)
    {rows, rest} = Enum.split(rows, @max_rows)

    counts =
      Enum.reduce(rows, %{inserted: 0, updated: 0, skipped: 0}, fn row, counts ->
        case upsert(row) do
          {:ok, :inserted} -> Map.update!(counts, :inserted, &(&1 + 1))
          {:ok, :updated} -> Map.update!(counts, :updated, &(&1 + 1))
          :skipped -> Map.update!(counts, :skipped, &(&1 + 1))
        end
      end)

    Map.put(counts, :truncated, rest != [])
  end

  defp upsert(attrs) do
    attrs = prepare(attrs)
    key = Client.name_key(attrs["company_name"])

    if key in [nil, ""] or String.length(key) < 2 do
      :skipped
    else
      case Repo.get_by(Client, name_key: key) do
        nil ->
          case %Client{} |> Client.changeset(attrs) |> Repo.insert() do
            {:ok, _} -> {:ok, :inserted}
            {:error, _} -> :skipped
          end

        %Client{} = client ->
          case client |> Client.changeset(filled_updates(client, attrs)) |> Repo.update() do
            {:ok, _} -> {:ok, :updated}
            {:error, _} -> :skipped
          end
      end
    end
  end

  defp prepare(attrs) do
    %{
      "company_name" => attrs["company_name"],
      "email" => clean_email(attrs["email"]),
      "phone" => attrs["phone"],
      "website_url" => normalize_website(present(attrs["website_url"]))
    }
  end

  defp clean_email(email) do
    case present(email) do
      nil -> nil
      email -> if(Regex.match?(~r/^[^\s]+@[^\s]+$/, email), do: email)
    end
  end

  # Blank cells on a later upload keep the values already stored.
  defp filled_updates(client, attrs) do
    %{
      "company_name" => attrs["company_name"],
      "email" => present(attrs["email"]) || client.email,
      "phone" => present(attrs["phone"]) || client.phone,
      "website_url" => normalize_website(present(attrs["website_url"])) || client.website_url
    }
  end

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(value), do: String.trim(value)

  defp normalize_website(nil), do: nil

  defp normalize_website(url) do
    url = String.trim(url)

    cond do
      url == "" -> nil
      String.match?(url, ~r/^https?:\/\//i) -> url
      true -> "https://" <> url
    end
  end
end
