defmodule CompanyContactFinder.Leads.BucketsTest do
  use CompanyContactFinder.DataCase, async: true

  import CompanyContactFinder.LeadStubs

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.{Lookup, Pipeline}

  defp await_analysed(id) do
    Leads.subscribe_lookup(id)

    unless Repo.get!(Lookup, id).status in [:done, :failed] do
      assert_receive {:lookup_updated, %{status: :done}}, 2_000
    end

    Leads.get_lookup!(id)
  end

  defp crawled_lookup(bucket \\ nil) do
    stub_all()
    lookup = Repo.insert!(%Lookup{company_name: "Acme Logistics", bucket_id: bucket && bucket.id})
    Pipeline.run(lookup.id)
    Leads.get_lookup!(lookup.id)
  end

  test "create_bucket/1 broadcasts and sets criteria_changed_at" do
    Leads.subscribe_buckets()
    assert {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    assert bucket.criteria_changed_at
    assert_received {:bucket_updated, %{id: id}} when id == bucket.id
  end

  test "the brief is scored against the lookup's bucket" do
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    test_pid = self()

    Req.Test.stub(CompanyContactFinder.AI.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:prompt, body})

      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => Jason.encode!(brief_content())}}]
      })
    end)

    stub_serper()
    stub_site()
    lookup = Repo.insert!(%Lookup{company_name: "Acme Logistics", bucket_id: bucket.id})
    Pipeline.run(lookup.id)

    assert_received {:prompt, body}
    assert body =~ "Lead bucket: Nairobi logistics firms"
    assert body =~ "Service we will offer: SSCC logistics labels"
    assert body =~ "Not a fit (disqualifiers): Already GS1 members"

    brief = Leads.get_lookup!(lookup.id).brief
    assert brief.fit == "strong"
    assert brief.pitch =~ "GTINs"
    assert brief.scored_bucket_id == bucket.id
  end

  test "list_buckets/0 includes lead counts, strong fits and average score" do
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    a = Repo.insert!(%Lookup{company_name: "A", bucket_id: bucket.id, status: :done})
    b = Repo.insert!(%Lookup{company_name: "B", bucket_id: bucket.id, status: :done})
    Repo.insert!(%Lookup{company_name: "C", bucket_id: bucket.id})
    Leads.save_brief(a, %{status: :done, lead_score: 80, fit: "strong"})
    Leads.save_brief(b, %{status: :done, lead_score: 40, fit: "weak"})

    assert [%{lead_count: 3, strong_count: 1, avg_score: avg}] = Leads.list_buckets()
    assert avg == 60.0
  end

  test "assign_bucket/2 moves a crawled lookup and rescores it" do
    lookup = crawled_lookup()
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())

    assert {:ok, moved} = Leads.assign_bucket(lookup, bucket.id)
    assert moved.bucket.id == bucket.id

    lookup = await_analysed(lookup.id)
    assert lookup.brief.scored_bucket_id == bucket.id
    refute Leads.brief_stale?(lookup)
  end

  test "assign_bucket/2 rejects a bucket that doesn't exist" do
    lookup = Repo.insert!(%Lookup{company_name: "Acme", status: :done})
    assert {:error, %Ecto.Changeset{}} = Leads.assign_bucket(lookup, "-1")
  end

  test "editing criteria makes briefs stale until rescored" do
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    lookup = crawled_lookup(bucket)
    refute Leads.brief_stale?(lookup)

    # Scores are stored to the second, so step past the scoring time.
    Repo.update_all(CompanyContactFinder.Leads.CompanyBrief,
      set: [scored_at: DateTime.add(DateTime.utc_now(:second), -60)]
    )

    {:ok, _bucket} = Leads.update_bucket(bucket, %{"services" => ["Traceability solutions"]})
    lookup = Leads.get_lookup!(lookup.id)
    assert Leads.brief_stale?(lookup)

    assert {:ok, 1} = Leads.rescore_bucket(lookup.bucket)
    refute Leads.brief_stale?(await_analysed(lookup.id))
  end

  test "renaming a bucket doesn't make briefs stale" do
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    lookup = crawled_lookup(bucket)

    {:ok, _} = Leads.update_bucket(bucket, %{"name" => "Renamed"})
    refute Leads.brief_stale?(Leads.get_lookup!(lookup.id))
  end

  test "deleting a bucket keeps its lookups" do
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    lookup = Repo.insert!(%Lookup{company_name: "Acme", bucket_id: bucket.id})

    assert {:ok, _} = Leads.delete_bucket(bucket)
    assert Repo.get!(Lookup, lookup.id).bucket_id == nil
  end

  test "start_bulk_lookups/2 puts lookups in the bucket" do
    stub_all()
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())

    assert {:ok, [lookup]} = Leads.start_bulk_lookups("Acme Logistics", bucket.id)
    assert lookup.bucket_id == bucket.id
    await_analysed(lookup.id)
  end
end
