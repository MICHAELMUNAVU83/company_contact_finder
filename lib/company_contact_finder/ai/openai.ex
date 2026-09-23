defmodule CompanyContactFinder.AI.OpenAI do
  @moduledoc """
  Minimal OpenAI Chat Completions client using structured outputs.

  The API key is read from `OPENAI_API_KEY` and the model from
  `OPENAI_MODEL` (see config).
  """
  require Logger

  @type result :: %{
          content: map(),
          model: String.t() | nil,
          prompt_tokens: integer() | nil,
          completion_tokens: integer() | nil
        }

  @doc "True if an API key is configured."
  def configured?, do: match?({:ok, _}, fetch_api_key(config()))

  @doc """
  Sends `messages` and returns the JSON object produced by the model,
  validated against `json_schema` by OpenAI (strict mode).
  """
  @spec structured_chat([map()], map(), keyword()) :: {:ok, result()} | {:error, term()}
  def structured_chat(messages, %{name: _, schema: _} = json_schema, opts \\ []) do
    config = config()

    with {:ok, api_key} <- fetch_api_key(config) do
      body = %{
        model: Keyword.get(opts, :model, config[:model]),
        messages: messages,
        response_format: %{type: "json_schema", json_schema: Map.put(json_schema, :strict, true)}
      }

      [
        base_url: config[:base_url],
        url: "/chat/completions",
        auth: {:bearer, api_key},
        json: body,
        receive_timeout: 60_000
      ]
      |> Keyword.merge(config[:req_options] || [])
      |> Req.post()
      |> handle_response()
    end
  end

  defp config, do: Application.fetch_env!(:company_contact_finder, :openai)

  defp fetch_api_key(config) do
    case config[:api_key] do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_openai_api_key}
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    case body do
      %{"choices" => [%{"message" => %{"refusal" => refusal}} | _]} when is_binary(refusal) ->
        {:error, {:openai_refused, refusal}}

      %{"choices" => [%{"message" => %{"content" => content}} | _]} when is_binary(content) ->
        case Jason.decode(content) do
          {:ok, decoded} when is_map(decoded) ->
            usage = body["usage"] || %{}

            {:ok,
             %{
               content: decoded,
               model: body["model"],
               prompt_tokens: usage["prompt_tokens"],
               completion_tokens: usage["completion_tokens"]
             }}

          _ ->
            {:error, :openai_invalid_json}
        end

      _ ->
        {:error, :openai_unexpected_response}
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    message = get_in(body, ["error", "message"]) || inspect(body)
    Logger.warning("OpenAI request failed with status #{status}: #{message}")
    {:error, {:openai_http_error, status}}
  end

  defp handle_response({:error, exception}) do
    Logger.warning("OpenAI request failed: #{Exception.message(exception)}")
    {:error, {:openai_request_failed, Exception.message(exception)}}
  end
end
