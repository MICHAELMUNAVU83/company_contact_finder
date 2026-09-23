defmodule CompanyContactFinder.AI.CompanyAnalystTest do
  use ExUnit.Case, async: true

  import CompanyContactFinder.LeadStubs

  alias CompanyContactFinder.AI.CompanyAnalyst
  alias CompanyContactFinder.Leads.{Contact, Lookup}

  @lookup %Lookup{
    company_name: "Acme Logistics",
    website_url: "https://acmelogistics.co.ke",
    scraped_text: "We move freight across East Africa."
  }
  @contacts [
    %Contact{
      type: :email,
      value: "sales@acmelogistics.co.ke",
      source_url: "https://acmelogistics.co.ke/contact"
    }
  ]

  test "sends a strict JSON schema request with the scraped text" do
    test_pid = self()

    Req.Test.stub(CompanyContactFinder.AI.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:request, Jason.decode!(body), Plug.Conn.get_req_header(conn, "authorization")}
      )

      Req.Test.json(conn, %{
        "model" => "test-model",
        "choices" => [%{"message" => %{"content" => Jason.encode!(brief_content())}}],
        "usage" => %{}
      })
    end)

    assert {:ok, attrs} = CompanyAnalyst.analyse(@lookup, @contacts)
    assert attrs.status == :done
    assert attrs.lead_score == 78
    assert [%{"value" => "sales@acmelogistics.co.ke"}] = attrs.contacts_analysis

    assert_received {:request, body, ["Bearer test-openai-key"]}
    assert body["model"] == "test-model"
    assert body["response_format"]["json_schema"]["strict"] == true
    assert body["response_format"]["json_schema"]["schema"]["additionalProperties"] == false

    user = Enum.find(body["messages"], &(&1["role"] == "user"))["content"]
    assert user =~ "We move freight across East Africa."
    assert user =~ "email: sales@acmelogistics.co.ke"
  end

  test "maps 'unknown' values to nil and clamps the score" do
    stub_openai(
      brief_content(%{"industry" => "unknown", "lead_score" => 150, "locations" => ["unknown"]})
    )

    assert {:ok, attrs} = CompanyAnalyst.analyse(@lookup, @contacts)
    assert attrs.industry == nil
    assert attrs.locations == []
    assert attrs.lead_score == 100
  end

  test "returns refusals as errors" do
    Req.Test.stub(CompanyContactFinder.AI.OpenAI, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"refusal" => "no", "content" => nil}}]})
    end)

    assert CompanyAnalyst.analyse(@lookup, @contacts) == {:error, {:openai_refused, "no"}}
  end
end
