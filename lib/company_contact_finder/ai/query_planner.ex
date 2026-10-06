defmodule CompanyContactFinder.AI.QueryPlanner do
  @moduledoc """
  Writes Google queries for a wide lead bucket. The queries look for lists
  and news that name companies. They are not company names.
  """

  alias CompanyContactFinder.AI.OpenAI
  alias CompanyContactFinder.Leads.Bucket

  @system_prompt """
  You write Google search queries that find lists, rankings, directories and
  news articles naming companies that match a lead bucket.

  Rules:
  - Return at most 24 queries.
  - Each query is a search string, not a company name.
  - Use the bucket's industries, locations and target description.
  - Prefer queries like "top {industry} companies in {place}" and
    "{industry} companies expanding in {place}".
  - Do not include instructions to the reader. Queries only.
  """

  @doc """
  Returns search query strings. Falls back to an error so the caller can
  use the narrow query list.
  """
  def plan(%Bucket{} = bucket) do
    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: user_prompt(bucket)}
    ]

    with {:ok, %{content: content}} <- OpenAI.structured_chat(messages, json_schema()) do
      queries =
        content
        |> Map.get("queries", [])
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
        |> Enum.take(24)

      {:ok, queries}
    end
  end

  defp user_prompt(bucket) do
    """
    Bucket: #{bucket.name}
    Target: #{bucket.target_description}
    Industries: #{Enum.join(bucket.industries, ", ")}
    Locations: #{Enum.join(bucket.locations, ", ")}
    """
  end

  defp json_schema do
    %{
      name: "search_queries",
      schema: %{
        type: "object",
        additionalProperties: false,
        required: ["queries"],
        properties: %{
          queries: %{type: "array", items: %{type: "string"}}
        }
      }
    }
  end
end
