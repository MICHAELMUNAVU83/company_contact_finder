defmodule CompanyContactFinder.Search do
  @moduledoc """
  The country lead searches are scoped to, set in `config :company_contact_finder, :search`.
  """

  @doc "Lowercase country code for Google's `gl` parameter and the country's TLD, e.g. `\"ke\"`."
  def country_code, do: config()[:country_code]

  @doc "Country name added to search queries, e.g. `\"Kenya\"`."
  def country_name, do: config()[:country_name]

  defp config, do: Application.get_env(:company_contact_finder, :search, [])
end
