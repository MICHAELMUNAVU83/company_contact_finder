defmodule CompanyContactFinder.LeadStubs do
  @moduledoc """
  Req.Test stubs for Serper, the crawled website and OpenAI.
  """

  @fixtures Path.expand("fixtures/html", __DIR__)

  def fixture(name), do: File.read!(Path.join(@fixtures, name))

  def serper_body(overrides \\ %{}) do
    Map.merge(
      %{
        "knowledgeGraph" => %{
          "title" => "Acme Logistics",
          "website" => "https://acmelogistics.co.ke/"
        },
        "organic" => [
          %{
            "title" => "Acme Logistics - LinkedIn",
            "link" => "https://www.linkedin.com/company/acme",
            "position" => 1
          },
          %{
            "title" => "Acme Logistics",
            "link" => "https://acmelogistics.co.ke/",
            "position" => 2
          }
        ]
      },
      overrides
    )
  end

  def stub_serper(body \\ serper_body()) do
    Req.Test.stub(CompanyContactFinder.Search.Serper, fn conn -> Req.Test.json(conn, body) end)
  end

  def stub_serper_error(status) do
    Req.Test.stub(CompanyContactFinder.Search.Serper, fn conn ->
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{"message" => "error"})
    end)
  end

  @doc "Stubs a site: a map of path => html (or {status, body})."
  def stub_site(pages \\ default_pages()) do
    Req.Test.stub(CompanyContactFinder.Scraper.Crawler, fn conn ->
      case Map.get(pages, conn.request_path) do
        nil ->
          Plug.Conn.send_resp(conn, 404, "not found")

        {:redirect, location} ->
          conn |> Plug.Conn.put_resp_header("location", location) |> Plug.Conn.send_resp(301, "")

        {:text, body} ->
          conn |> Plug.Conn.put_resp_content_type("text/plain") |> Plug.Conn.send_resp(200, body)

        html ->
          conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_resp(200, html)
      end
    end)
  end

  def default_pages do
    %{
      "/robots.txt" => {:text, "User-agent: *\nDisallow: /private\n"},
      "/" => fixture("home.html"),
      "/get-in-touch" => fixture("contact.html"),
      "/about-us" => "<html><body><h1>About</h1><p>Founded in 2010.</p></body></html>"
    }
  end

  def brief_content(overrides \\ %{}) do
    Map.merge(
      %{
        "summary" => "Acme Logistics is a Nairobi freight forwarder.",
        "industry" => "Logistics",
        "products_services" => ["Freight forwarding", "Warehousing"],
        "locations" => ["Nairobi, Kenya"],
        "company_size_hint" => "small",
        "target_customers" => "Importers and exporters",
        "contacts_analysis" => [
          %{
            "value" => "sales@acmelogistics.co.ke",
            "role" => "sales",
            "quality" => "high",
            "note" => "Sales inbox"
          },
          %{
            "value" => "made-up@nowhere.com",
            "role" => "sales",
            "quality" => "high",
            "note" => "Invented"
          }
        ],
        "best_contact" => "sales@acmelogistics.co.ke",
        "fit" => "strong",
        "fit_reason" => "Packaged goods sold through retailers",
        "pitch" => "Offer GTINs so they can list with supermarkets",
        "lead_score" => 78,
        "lead_score_reason" => "Clear business and a sales inbox",
        "outreach_angle" => "They offer customs clearance"
      },
      overrides
    )
  end

  def stub_openai(content \\ brief_content()) do
    Req.Test.stub(CompanyContactFinder.AI.OpenAI, fn conn ->
      Req.Test.json(conn, %{
        "model" => "test-model",
        "choices" => [
          %{"message" => %{"role" => "assistant", "content" => Jason.encode!(content)}}
        ],
        "usage" => %{"prompt_tokens" => 1200, "completion_tokens" => 300}
      })
    end)
  end

  def stub_openai_error(status) do
    Req.Test.stub(CompanyContactFinder.AI.OpenAI, fn conn ->
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{"error" => %{"message" => "nope"}})
    end)
  end

  def bucket_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Nairobi logistics firms",
        "target_description" => "Freight and logistics companies in Nairobi",
        "industries" => "Logistics, Freight",
        "locations" => "Nairobi",
        "company_sizes" => ["small", "medium"],
        "service" => "SSCC logistics labels",
        "service_details" => "Labels and training",
        "disqualifiers" => "Already GS1 members"
      },
      overrides
    )
  end

  def stub_all do
    stub_serper()
    stub_site()
    stub_openai()
  end
end
