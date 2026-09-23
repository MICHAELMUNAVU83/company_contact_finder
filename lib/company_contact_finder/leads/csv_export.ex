defmodule CompanyContactFinder.Leads.CSVExport do
  @moduledoc """
  Exports lookups as CSV, one row per company.

  Cells that spreadsheet apps would run as formulas are prefixed with `'`
  (CSV injection); phone numbers like `+254…` are left alone.
  """

  alias CompanyContactFinder.Leads.Lookup

  @headers ~w(company bucket website status lead_score fit fit_reason industry
              company_size summary best_contact emails phones socials pitch
              outreach_angle searched_at)

  @spec to_csv([%Lookup{}]) :: String.t()
  def to_csv(lookups) do
    rows = Enum.map(lookups, &row/1)
    [@headers | rows] |> Enum.map_join("", &encode_row/1)
  end

  defp row(%Lookup{} = lookup) do
    brief = if is_struct(lookup.brief), do: lookup.brief, else: nil
    contacts = if is_list(lookup.contacts), do: lookup.contacts, else: []

    values = fn type ->
      contacts |> Enum.filter(&(&1.type == type)) |> Enum.map_join("; ", & &1.value)
    end

    bucket = if is_struct(lookup.bucket), do: lookup.bucket, else: nil

    [
      lookup.company_name,
      bucket && bucket.name,
      lookup.website_url,
      lookup.status,
      brief && brief.lead_score,
      brief && brief.fit,
      brief && brief.fit_reason,
      brief && brief.industry,
      brief && brief.company_size_hint,
      brief && brief.summary,
      brief && brief.best_contact,
      values.(:email),
      values.(:phone),
      values.(:social),
      brief && brief.pitch,
      brief && brief.outreach_angle,
      lookup.inserted_at && DateTime.to_iso8601(lookup.inserted_at)
    ]
  end

  defp encode_row(values), do: Enum.map_join(values, ",", &encode_cell/1) <> "\r\n"

  @doc false
  def encode_cell(nil), do: ""

  def encode_cell(value) do
    value = value |> to_string() |> neutralize_formula()

    if String.contains?(value, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
  end

  defp neutralize_formula(value) do
    cond do
      value =~ ~r/^\+?[\d\s;+]+$/ -> value
      String.starts_with?(value, ["=", "+", "-", "@", "\t", "\r"]) -> "'" <> value
      true -> value
    end
  end
end
