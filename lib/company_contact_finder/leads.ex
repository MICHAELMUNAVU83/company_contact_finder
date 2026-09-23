defmodule CompanyContactFinder.Leads do
  @moduledoc """
  The Leads context: lookups, the contacts found for them and their AI briefs.

  Progress is broadcast over PubSub:

    * `"lookups"` – `{:lookup_updated, lookup}` for any lookup (index page)
    * `"buckets"` – `{:bucket_updated, bucket}` / `{:bucket_deleted, bucket}`
    * `"lookup:<id>"` – `{:lookup_updated, lookup}`, `{:contacts_added, contacts}`,
      `{:contacts_updated, contacts}` and `{:brief_updated, brief}`
  """

  import Ecto.Query

  alias CompanyContactFinder.Repo
  alias CompanyContactFinder.Leads.{Bucket, CompanyBrief, Contact, Lookup, Pipeline}

  @pubsub CompanyContactFinder.PubSub

  ## PubSub

  def subscribe_lookups, do: Phoenix.PubSub.subscribe(@pubsub, "lookups")
  def subscribe_lookup(id), do: Phoenix.PubSub.subscribe(@pubsub, "lookup:#{id}")
  def subscribe_buckets, do: Phoenix.PubSub.subscribe(@pubsub, "buckets")

  defp broadcast_lookup(%Lookup{} = lookup) do
    Phoenix.PubSub.broadcast(@pubsub, "lookups", {:lookup_updated, lookup})
    Phoenix.PubSub.broadcast(@pubsub, "lookup:#{lookup.id}", {:lookup_updated, lookup})
  end

  defp broadcast(lookup_id, message),
    do: Phoenix.PubSub.broadcast(@pubsub, "lookup:#{lookup_id}", message)

  ## Queries

  @doc """
  Lists recent lookups with their brief and contact count.

  Options: `:sort` (`:recent` or `:score`), `:bucket_id`, `:limit` (default 100).
  """
  def list_lookups(opts \\ []) do
    contact_counts =
      from c in Contact,
        group_by: c.lookup_id,
        select: %{lookup_id: c.lookup_id, count: count(c.id)}

    query =
      from l in Lookup,
        left_join: b in assoc(l, :brief),
        left_join: cc in subquery(contact_counts),
        on: cc.lookup_id == l.id,
        left_join: bk in assoc(l, :bucket),
        preload: [brief: b, bucket: bk],
        select_merge: %{contact_count: coalesce(cc.count, 0)},
        limit: ^Keyword.get(opts, :limit, 100)

    query =
      case Keyword.get(opts, :sort, :recent) do
        :score ->
          order_by(query, [l, b], desc_nulls_last: b.lead_score, desc: l.inserted_at, desc: l.id)

        _ ->
          order_by(query, [l], desc: l.inserted_at, desc: l.id)
      end

    query =
      case Keyword.get(opts, :bucket_id) do
        nil -> query
        bucket_id -> where(query, [l], l.bucket_id == ^bucket_id)
      end

    Repo.all(query)
  end

  @doc "Gets a lookup with its contacts, brief and bucket. Raises if not found."
  def get_lookup!(id) do
    Lookup
    |> Repo.get!(id)
    |> Repo.preload([:bucket, brief: [], contacts: from(c in Contact, order_by: [c.type, c.id])])
  end

  @doc "Reloads a lookup with its brief and contact count, as used by the index."
  def get_lookup_summary(id) do
    Repo.one(
      from l in Lookup,
        where: l.id == ^id,
        left_join: b in assoc(l, :brief),
        left_join: c in assoc(l, :contacts),
        left_join: bk in assoc(l, :bucket),
        group_by: [l.id, b.id, bk.id],
        preload: [brief: b, bucket: bk],
        select_merge: %{contact_count: count(c.id)}
    )
  end

  @doc """
  Lookups with contacts, brief and bucket preloaded, for CSV export.
  Options: `:ids`, `:bucket_id`. Bucket exports are ranked by score.
  """
  def list_lookups_for_export(opts \\ []) do
    query = from l in Lookup, left_join: b in assoc(l, :brief), limit: 5000

    query =
      case Keyword.fetch(opts, :bucket_id) do
        {:ok, id} ->
          query
          |> where([l], l.bucket_id == ^id)
          |> order_by([l, b], desc_nulls_last: b.lead_score, desc: l.inserted_at, desc: l.id)

        :error ->
          order_by(query, [l], desc: l.inserted_at, desc: l.id)
      end

    query =
      case Keyword.fetch(opts, :ids) do
        {:ok, ids} -> where(query, [l], l.id in ^ids)
        :error -> query
      end

    query
    |> Repo.all()
    |> Repo.preload([:brief, :bucket, contacts: from(c in Contact, order_by: [c.type, c.id])])
  end

  def list_contacts(%Lookup{id: id}) do
    Repo.all(from c in Contact, where: c.lookup_id == ^id, order_by: [c.type, c.id])
  end

  def change_lookup(%Lookup{} = lookup \\ %Lookup{}, attrs \\ %{}),
    do: Lookup.create_changeset(lookup, attrs)

  def change_website(%Lookup{} = lookup, attrs \\ %{}),
    do: Lookup.website_changeset(lookup, attrs)

  ## Starting work

  @doc "Creates a lookup and runs the pipeline in the background."
  def start_lookup(attrs) do
    with {:ok, lookup} <- create_lookup(attrs) do
      run_async(fn -> Pipeline.run(lookup.id) end)
      {:ok, lookup}
    end
  end

  @doc """
  Creates lookups for many company names (one per line / comma separated)
  and processes them with bounded concurrency.
  """
  def start_bulk_lookups(text, bucket_id \\ nil) when is_binary(text) do
    names =
      text
      |> String.split(["\n", "\r", ","])
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq_by(&String.downcase/1)
      |> Enum.take(200)

    lookups =
      Enum.flat_map(names, fn name ->
        case create_lookup(%{"company_name" => name, "bucket_id" => bucket_id}) do
          {:ok, lookup} -> [lookup]
          {:error, _} -> []
        end
      end)

    ids = Enum.map(lookups, & &1.id)

    max_concurrency =
      Application.get_env(:company_contact_finder, :lookups, [])[:max_concurrency] || 3

    run_async(fn ->
      ids
      |> Task.async_stream(&Pipeline.run/1,
        max_concurrency: max_concurrency,
        timeout: :infinity,
        ordered: false
      )
      |> Stream.run()
    end)

    {:ok, lookups}
  end

  @doc "Re-runs the pipeline, using the user's website instead of searching."
  def rerun_with_website(%Lookup{} = lookup, attrs) do
    changeset = Lookup.website_changeset(lookup, attrs)

    with :ok <- ensure_idle(lookup),
         {:ok, lookup} <- Repo.update(changeset) do
      {:ok, lookup} = reset_for_rerun(lookup)
      run_async(fn -> Pipeline.run(lookup.id) end)
      {:ok, lookup}
    end
  end

  @doc "Re-runs the whole pipeline for a lookup."
  def rerun_lookup(%Lookup{} = lookup) do
    with :ok <- ensure_idle(lookup) do
      {:ok, lookup} = reset_for_rerun(lookup)
      run_async(fn -> Pipeline.run(lookup.id) end)
      {:ok, lookup}
    end
  end

  @doc "Retries only the AI brief using the stored scraped text."
  def retry_brief(%Lookup{} = lookup) do
    with :ok <- ensure_idle(lookup) do
      run_async(fn -> Pipeline.analyse(lookup.id) end)
      :ok
    end
  end

  @doc """
  Moves a lookup to another bucket (or none) and rescores its brief against
  the new bucket if the site has already been crawled.
  """
  def assign_bucket(%Lookup{} = lookup, bucket_id) do
    changeset = Lookup.bucket_changeset(lookup, %{bucket_id: blank_to_nil(bucket_id)})

    with :ok <- ensure_idle(lookup),
         {:ok, updated} <- Repo.update(changeset) do
      updated = Repo.preload(updated, :bucket, force: true)
      broadcast_lookup(updated)

      if updated.status == :done and updated.scraped_text do
        run_async(fn -> Pipeline.analyse(updated.id) end)
      end

      {:ok, updated}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @doc "True while the pipeline is working on the lookup."
  def in_progress?(%Lookup{status: status}),
    do: status in [:pending, :searching, :crawling, :analysing]

  # Runs that haven't reported progress for this long are assumed dead
  # (e.g. the server restarted mid-run) and may be restarted.
  @stale_after_seconds 600

  defp ensure_idle(lookup) do
    # Re-read the status so a stale struct can't start a second run.
    current = Repo.get!(Lookup, lookup.id)
    stale? = DateTime.diff(DateTime.utc_now(), current.updated_at) > @stale_after_seconds

    if in_progress?(current) and not stale?, do: {:error, :in_progress}, else: :ok
  end

  defp run_async(fun) do
    {:ok, _pid} = Task.Supervisor.start_child(CompanyContactFinder.TaskSupervisor, fun)
  end

  defp create_lookup(attrs) do
    %Lookup{}
    |> Lookup.create_changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&broadcast_lookup/1)
  end

  defp reset_for_rerun(lookup) do
    Repo.transaction(fn ->
      Repo.delete_all(from c in Contact, where: c.lookup_id == ^lookup.id)
      Repo.delete_all(from b in CompanyBrief, where: b.lookup_id == ^lookup.id)

      lookup
      |> Lookup.progress_changeset(%{
        status: :pending,
        error: nil,
        scraped_text: nil,
        pages_crawled: 0
      })
      |> Repo.update!()
    end)
    |> tap_ok(&broadcast_lookup/1)
  end

  ## Buckets

  @doc "Lists buckets with lead counts, strong fits and average score."
  def list_buckets do
    Repo.all(
      from bk in Bucket,
        left_join: l in assoc(bk, :lookups),
        left_join: b in assoc(l, :brief),
        group_by: bk.id,
        order_by: [desc: bk.updated_at, desc: bk.id],
        select_merge: %{
          lead_count: count(l.id),
          strong_count: filter(count(b.id), b.fit == "strong"),
          avg_score: type(avg(b.lead_score), :float)
        }
    )
  end

  @doc "Bucket id/name pairs for select inputs."
  def bucket_options do
    Repo.all(from bk in Bucket, order_by: bk.name, select: {bk.name, bk.id})
  end

  def get_bucket!(id), do: Repo.get!(Bucket, id)

  def change_bucket(%Bucket{} = bucket \\ %Bucket{}, attrs \\ %{}),
    do: Bucket.changeset(bucket, attrs)

  def create_bucket(attrs) do
    %Bucket{}
    |> Bucket.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&Phoenix.PubSub.broadcast(@pubsub, "buckets", {:bucket_updated, &1}))
  end

  @doc """
  Updates a bucket's criteria. Existing briefs keep their scores until the
  bucket is rescored (see `rescore_bucket/1`).
  """
  def update_bucket(%Bucket{} = bucket, attrs) do
    bucket
    |> Bucket.changeset(attrs)
    |> Repo.update()
    |> tap_ok(&Phoenix.PubSub.broadcast(@pubsub, "buckets", {:bucket_updated, &1}))
  end

  @doc "Deletes a bucket. Its lookups are kept, without a bucket."
  def delete_bucket(%Bucket{} = bucket) do
    bucket
    |> Repo.delete()
    |> tap_ok(&Phoenix.PubSub.broadcast(@pubsub, "buckets", {:bucket_deleted, &1}))
  end

  @doc """
  Re-runs the AI brief for every crawled, idle lookup in the bucket so scores
  reflect its current criteria. Returns the number of lookups queued.
  """
  def rescore_bucket(%Bucket{id: bucket_id}) do
    ids =
      Repo.all(
        from l in Lookup,
          where: l.bucket_id == ^bucket_id and l.status == :done and not is_nil(l.scraped_text),
          select: l.id
      )

    max_concurrency =
      Application.get_env(:company_contact_finder, :lookups, [])[:max_concurrency] || 3

    if ids != [] do
      run_async(fn ->
        ids
        |> Task.async_stream(&Pipeline.analyse/1,
          max_concurrency: max_concurrency,
          timeout: :infinity,
          ordered: false
        )
        |> Stream.run()
      end)
    end

    {:ok, length(ids)}
  end

  @doc """
  True if the lookup's brief was scored against a different bucket, or
  before the bucket's scoring criteria last changed.
  """
  def brief_stale?(%Lookup{brief: %CompanyBrief{status: :done} = brief} = lookup) do
    bucket = if match?(%Bucket{}, lookup.bucket), do: lookup.bucket, else: nil

    cond do
      brief.scored_bucket_id != lookup.bucket_id ->
        true

      bucket && is_nil(brief.scored_at) ->
        true

      bucket && bucket.criteria_changed_at ->
        DateTime.compare(brief.scored_at, bucket.criteria_changed_at) == :lt

      true ->
        false
    end
  end

  def brief_stale?(_lookup), do: false

  ## Used by the pipeline

  @doc false
  def update_progress(%Lookup{} = lookup, attrs) do
    lookup
    |> Lookup.progress_changeset(attrs)
    |> Repo.update()
    |> tap_ok(&broadcast_lookup/1)
  end

  @doc false
  # Inserts contacts, skipping ones already found. Returns the new ones.
  def add_contacts(%Lookup{id: lookup_id}, contacts) do
    now = DateTime.utc_now(:second)

    entries =
      contacts
      |> Enum.uniq_by(&{&1.type, &1.value})
      |> Enum.map(fn c ->
        %{
          lookup_id: lookup_id,
          type: c.type,
          value: String.slice(c.value, 0, 255),
          source_url: c.source_url,
          inserted_at: now
        }
      end)

    {_count, inserted} =
      Repo.insert_all(Contact, entries,
        on_conflict: :nothing,
        conflict_target: [:lookup_id, :type, :value],
        returning: true
      )

    if inserted != [], do: broadcast(lookup_id, {:contacts_added, inserted})
    inserted
  end

  @doc false
  def save_brief(%Lookup{id: lookup_id}, attrs) do
    brief = Repo.get_by(CompanyBrief, lookup_id: lookup_id) || %CompanyBrief{lookup_id: lookup_id}

    brief
    |> CompanyBrief.changeset(attrs)
    |> Repo.insert_or_update()
    |> tap_ok(&broadcast(lookup_id, {:brief_updated, &1}))
  end

  @doc false
  # Applies AI role/quality/notes to matching contacts.
  def apply_contact_analysis(%Lookup{id: lookup_id} = lookup, analysis) do
    by_value = Map.new(analysis, &{&1["value"], &1})

    updated =
      lookup
      |> list_contacts()
      |> Enum.flat_map(fn contact ->
        case Map.get(by_value, contact.value) do
          nil ->
            []

          item ->
            contact
            |> Contact.analysis_changeset(%{
              role: item["role"],
              quality: item["quality"],
              ai_note: item["note"]
            })
            |> Repo.update()
            |> case do
              {:ok, contact} -> [contact]
              {:error, _} -> []
            end
        end
      end)

    if updated != [], do: broadcast(lookup_id, {:contacts_updated, updated})
    updated
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(error, _fun), do: error
end
