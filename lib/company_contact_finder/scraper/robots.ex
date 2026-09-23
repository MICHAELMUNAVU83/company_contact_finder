defmodule CompanyContactFinder.Scraper.Robots do
  @moduledoc """
  Minimal robots.txt support: `Disallow`/`Allow` prefix rules for our
  user agent or `*`. The longest matching rule wins, as in RFC 9309.
  """

  @agent "gs1kenyaleadfinder"

  @type rules :: [{:allow | :disallow, String.t()}]

  @spec parse(String.t() | nil) :: rules()
  def parse(nil), do: []

  def parse(body) when is_binary(body) do
    groups =
      body
      |> String.split(~r/\r?\n/)
      |> Enum.map(&(&1 |> String.split("#", parts: 2) |> hd() |> String.trim()))
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&parse_line/1)
      |> Enum.reject(&is_nil/1)
      |> group()

    Map.get(groups, @agent) || Map.get(groups, "*", [])
  end

  @spec allowed?(rules(), String.t()) :: boolean()
  def allowed?(rules, path) do
    path = if path in [nil, ""], do: "/", else: path

    rules
    |> Enum.filter(fn {_kind, prefix} -> prefix != "" and String.starts_with?(path, prefix) end)
    |> Enum.max_by(fn {kind, prefix} -> {String.length(prefix), kind == :allow} end, fn ->
      {:allow, ""}
    end)
    |> elem(0)
    |> Kernel.==(:allow)
  end

  defp parse_line(line) do
    case String.split(line, ":", parts: 2) do
      [key, value] -> {String.downcase(String.trim(key)), String.trim(value)}
      _ -> nil
    end
  end

  # Groups consecutive user-agent lines with the rules that follow them.
  defp group(lines) do
    {groups, _agents, _in_rules} =
      Enum.reduce(lines, {%{}, [], false}, fn
        {"user-agent", agent}, {groups, agents, in_rules} ->
          agents = if in_rules, do: [], else: agents
          {groups, [String.downcase(agent) | agents], false}

        {key, value}, {groups, agents, _} when key in ["allow", "disallow"] ->
          rule = {if(key == "allow", do: :allow, else: :disallow), value}

          groups =
            Enum.reduce(
              agents,
              groups,
              &Map.update(&2, &1, [rule], fn rules -> rules ++ [rule] end)
            )

          {groups, agents, true}

        _other, acc ->
          acc
      end)

    groups
  end
end
