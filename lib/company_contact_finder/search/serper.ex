defmodule CompanyContactFinder.Search.Serper do
  @moduledoc """
  Client for the Serper.dev Google Search API.

  See https://serper.dev. The API key is read from `SERPER_API_KEY`.
  """
  require Logger

  alias CompanyContactFinder.Search

  @doc """
  Runs a Google search and returns the decoded response body. Results are
  localised to `CompanyContactFinder.Search.country_code/0` unless a
  `:country` option is given.
  """
  @spec search(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def search(query, opts \\ []) do
    config = Application.fetch_env!(:company_contact_finder, :serper)

    with {:ok, api_key} <- fetch_api_key(config) do
      [
        base_url: config[:base_url],
        url: "/search",
        headers: [{"x-api-key", api_key}],
        json: %{
          q: query,
          num: Keyword.get(opts, :num, 10),
          gl: Keyword.get(opts, :country, Search.country_code())
        },
        receive_timeout: 15_000
      ]
      |> Keyword.merge(config[:req_options] || [])
      |> Req.post()
      |> handle_response()
    end
  end

  defp fetch_api_key(config) do
    case config[:api_key] do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_serper_api_key}
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) when is_map(body),
    do: {:ok, body}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    Logger.warning("Serper search failed with status #{status}: #{inspect(body)}")
    {:error, {:serper_http_error, status}}
  end

  defp handle_response({:error, exception}) do
    Logger.warning("Serper search request failed: #{Exception.message(exception)}")
    {:error, {:serper_request_failed, Exception.message(exception)}}
  end
end
