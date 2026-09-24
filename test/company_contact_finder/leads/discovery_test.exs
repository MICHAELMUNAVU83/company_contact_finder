defmodule CompanyContactFinder.Leads.DiscoveryTest do
  use CompanyContactFinder.DataCase, async: true

  import CompanyContactFinder.LeadStubs

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.{Bucket, Discovery, Lookup}

  test "queries/1 searches each industry in the first location" do
    bucket = %Bucket{
      target_description: "Freight firms",
      industries: ["Logistics", "Freight"],
      locations: ["Nairobi", "Mombasa"]
    }

    assert Discovery.queries(bucket) == [
             "top Logistics companies in Nairobi Kenya",
             "list of Logistics companies in Nairobi Kenya",
             "top Freight companies in Nairobi Kenya",
             "list of Freight companies in Nairobi Kenya"
           ]

    assert [
             "top Pharmaceutical makers companies in Kenya" | _
           ] = Discovery.queries(%Bucket{target_description: "Pharmaceutical makers"})
  end

  test "suggests companies named in the pages it reads, minus existing leads" do
    stub_discovery()
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    Repo.insert!(%Lookup{company_name: "acme logistics", bucket_id: bucket.id})

    assert {:ok, %{queries: [_ | _], suggestions: suggestions}} =
             Leads.discover_companies(bucket)

    # Invented names are dropped, strong matches come first and unknown sources are cleared.
    assert [
             %{
               name: "Bidii Freight",
               fit: "strong",
               source_url: "https://news.example.co.ke/top-logistics"
             },
             %{name: "Chui Couriers", fit: "possible", source_url: nil}
           ] = suggestions
  end

  test "sends the page text and bucket to OpenAI" do
    stub_serper(discovery_serper_body())
    stub_site(discovery_pages())
    test = self()

    Req.Test.stub(CompanyContactFinder.AI.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      prompt = body |> Jason.decode!() |> get_in(["messages", Access.at(1), "content"])
      send(test, {:prompt, prompt})

      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => Jason.encode!(%{"companies" => []})}}]
      })
    end)

    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    assert {:ok, %{suggestions: []}} = Discovery.discover(bucket)
    assert_received {:prompt, prompt}
    assert prompt =~ "Bidii Freight"
    assert prompt =~ "Target leads: Freight and logistics companies in Nairobi"
    refute prompt =~ "facebook.com"
  end

  test "returns the search error when every search fails" do
    stub_serper_error(401)
    {:ok, bucket} = Leads.create_bucket(bucket_attrs())
    assert {:error, {:serper_http_error, 401}} = Discovery.discover(bucket)
  end
end
