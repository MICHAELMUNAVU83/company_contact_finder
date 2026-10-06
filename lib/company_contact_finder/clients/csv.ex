defmodule CompanyContactFinder.Clients.CSV do
  @moduledoc """
  Reads a client spreadsheet export.

  A header row may name `company`, `email`, `phone` and `website`. Without
  that header, each line is a company name.
  """

  @company ~w(company company_name companyname name organisation organization)
  @email ~w(email e-mail email_address emailaddress)
  @phone ~w(phone telephone mobile tel phone_number)
  @website ~w(website website_url url site web)

  @doc "Returns a list of maps with string keys `company_name`, `email`, `phone`, `website_url`."
  def parse(text) when is_binary(text) do
    rows =
      text
      |> String.trim_leading("\uFEFF")
      |> String.split(~r/\r\n|\n|\r/)
      |> Enum.map(&parse_line/1)
      |> Enum.reject(fn cells -> Enum.all?(cells, &(&1 == "")) end)

    case rows do
      [] ->
        []

      [first | rest] ->
        if header?(first) do
          map_rows(header_indexes(first), rest)
        else
          Enum.flat_map(rows, fn
            [company | _] -> [%{"company_name" => company}]
            _ -> []
          end)
        end
    end
  end

  defp header?(cells) do
    Enum.any?(cells, &(normalize_header(&1) in @company))
  end

  defp header_indexes(cells) do
    cells
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {cell, index}, acc ->
      key = normalize_header(cell)

      cond do
        key in @company -> Map.put(acc, "company_name", index)
        key in @email -> Map.put(acc, "email", index)
        key in @phone -> Map.put(acc, "phone", index)
        key in @website -> Map.put(acc, "website_url", index)
        true -> acc
      end
    end)
  end

  defp map_rows(indexes, rows) do
    Enum.flat_map(rows, fn cells ->
      company = cell(cells, indexes["company_name"])

      if company in [nil, ""] do
        []
      else
        [
          %{
            "company_name" => company,
            "email" => cell(cells, indexes["email"]),
            "phone" => cell(cells, indexes["phone"]),
            "website_url" => cell(cells, indexes["website_url"])
          }
        ]
      end
    end)
  end

  defp cell(_cells, nil), do: nil

  defp cell(cells, index) do
    case Enum.at(cells, index) do
      nil -> nil
      value -> String.trim(value)
    end
  end

  defp normalize_header(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "")
  end

  defp parse_line(line), do: parse_line(line, "", false, [])

  defp parse_line(<<>>, field, _quoted, acc), do: Enum.reverse([String.trim(field) | acc])

  defp parse_line(<<"\"\"", rest::binary>>, field, true, acc),
    do: parse_line(rest, field <> "\"", true, acc)

  defp parse_line(<<"\"", rest::binary>>, field, true, acc),
    do: parse_line(rest, field, false, acc)

  defp parse_line(<<"\"", rest::binary>>, "", false, acc),
    do: parse_line(rest, "", true, acc)

  defp parse_line(<<",", rest::binary>>, field, false, acc),
    do: parse_line(rest, "", false, [String.trim(field) | acc])

  defp parse_line(<<char::utf8, rest::binary>>, field, quoted, acc),
    do: parse_line(rest, field <> <<char::utf8>>, quoted, acc)
end
