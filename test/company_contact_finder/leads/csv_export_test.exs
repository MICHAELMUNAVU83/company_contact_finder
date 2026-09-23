defmodule CompanyContactFinder.Leads.CSVExportTest do
  use ExUnit.Case, async: true

  alias CompanyContactFinder.Leads.{CompanyBrief, Contact, CSVExport, Lookup}

  test "exports one row per lookup with contacts joined" do
    lookup = %Lookup{
      company_name: "Acme, Inc",
      website_url: "https://acme.com",
      status: :done,
      inserted_at: ~U[2026-09-23 10:00:00Z],
      bucket: %CompanyContactFinder.Leads.Bucket{name: "Food makers"},
      brief: %CompanyBrief{
        lead_score: 80,
        summary: "Says \"hi\"",
        industry: "Logistics",
        fit: "strong",
        fit_reason: "Makes food"
      },
      contacts: [
        %Contact{type: :email, value: "a@acme.com"},
        %Contact{type: :email, value: "b@acme.com"},
        %Contact{type: :phone, value: "+254700123456"}
      ]
    }

    [header, row] =
      lookup |> List.wrap() |> CSVExport.to_csv() |> String.split("\r\n", trim: true)

    assert header =~ "company,bucket,website,status,lead_score,fit"
    assert row =~ ~s("Acme, Inc",Food makers,https://acme.com,done,80,strong,Makes food,Logistics)
    assert row =~ ~s("Says ""hi""")
    assert row =~ "a@acme.com; b@acme.com,+254700123456"
  end

  test "neutralizes formulas but keeps phone numbers" do
    assert CSVExport.encode_cell(~s|=HYPERLINK("x")|) == ~s|"'=HYPERLINK(""x"")"|
    assert CSVExport.encode_cell("@SUM(A1)") == "'@SUM(A1)"
    assert CSVExport.encode_cell("+254700123456") == "+254700123456"
    assert CSVExport.encode_cell(nil) == ""
  end
end
