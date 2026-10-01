defmodule CompanyContactFinder.Outreach do
  @moduledoc """
  Builds campaign previews and sends them only when a campaign is fired.

  Scoring a lead never calls this module.
  """

  import Ecto.Query

  alias Swoosh.Email
  alias CompanyContactFinder.AI.OpenAI
  alias CompanyContactFinder.Mailer
  alias CompanyContactFinder.Outreach.Message
  alias CompanyContactFinder.Repo
  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Bucket

  @default_subject "{{product}} for {{company}}"
  @default_template """
  Hello,

  {{company}} looks like a fit for {{product}}.

  {{pitch}}

  The contact we found is {{contact}}.
  """

  @doc "Done leads in the bucket, best score first, with contacts loaded."
  def campaign_leads(%Bucket{id: id}) do
    [bucket_id: id, sort: :score, limit: 100]
    |> Leads.list_lookups()
    |> Enum.filter(&(&1.status == :done))
    |> Repo.preload([:contacts, brief: :recommended_product])
  end

  @doc """
  Renders one preview per lead. Does not send mail and does not write rows.
  """
  def preview(%Bucket{} = bucket, lookups) do
    sent = sent_lookup_ids(bucket.id)

    Enum.map(lookups, fn lookup ->
      draft = render(bucket, lookup)
      Map.put(draft, :sent?, lookup.id in sent)
    end)
  end

  @doc """
  Sends every preview that has a recipient and has not already been sent.
  Returns `%{sent: n, skipped: n}`.
  """
  def fire(%Bucket{} = bucket, previews) when is_list(previews) do
    sent = sent_lookup_ids(bucket.id)

    Enum.reduce(previews, %{sent: 0, skipped: 0}, fn preview, counts ->
      cond do
        preview.sent? or preview.lookup_id in sent ->
          %{counts | skipped: counts.skipped + 1}

        blank?(preview.to) or blank?(preview.subject) or blank?(preview.body) or preview.error ->
          %{counts | skipped: counts.skipped + 1}

        true ->
          case deliver(bucket, preview) do
            :ok -> %{counts | sent: counts.sent + 1}
            :skipped -> %{counts | skipped: counts.skipped + 1}
          end
      end
    end)
  end

  defp render(%Bucket{} = bucket, lookup) do
    product = product_for(bucket, lookup)
    fields = fields(lookup, product)
    to = recipient(lookup)

    base = %{
      lookup_id: lookup.id,
      company: lookup.company_name,
      to: to,
      cc: product && product.owner_email,
      subject: nil,
      body: nil,
      error: if(blank?(to), do: "No email address on this lead")
    }

    cond do
      base.error ->
        base

      bucket.email_mode == "dynamic" ->
        dynamic(bucket, lookup, product, base)

      true ->
        %{
          base
          | subject: fill(present(bucket.email_subject) || @default_subject, fields),
            body: fill(present(bucket.email_template) || @default_template, fields)
        }
    end
  end

  defp dynamic(bucket, lookup, product, base) do
    messages = [
      %{
        role: "system",
        content: """
        Write one plain-text sales email. Use only the facts you are given.
        Do not invent prices, people, or offers. Return a subject and a body.
        The user's instructions follow.

        #{bucket.email_prompt || "Write a short first email."}
        """
      },
      %{
        role: "user",
        content: """
        Company: #{lookup.company_name}
        Product: #{product && product.name}
        Contact: #{base.to}
        Brief: #{lookup.brief && lookup.brief.summary}
        Pitch: #{lookup.brief && lookup.brief.pitch}
        Angle: #{lookup.brief && lookup.brief.outreach_angle}
        """
      }
    ]

    case OpenAI.structured_chat(messages, email_schema()) do
      {:ok, %{content: %{"subject" => subject, "body" => body}}}
      when is_binary(subject) and is_binary(body) ->
        %{base | subject: String.trim(subject), body: String.trim(body)}

      {:error, reason} ->
        %{base | error: "Could not draft this email (#{inspect(reason)})"}
    end
  end

  defp deliver(bucket, preview) do
    email =
      Email.new()
      |> Email.to(preview.to)
      |> Email.from(from_address())
      |> Email.subject(preview.subject)
      |> Email.text_body(preview.body <> opt_out())

    email =
      if blank?(preview.cc) or preview.cc == preview.to,
        do: email,
        else: Email.cc(email, preview.cc)

    case Mailer.deliver(email) do
      {:ok, _} ->
        %Message{}
        |> Ecto.Changeset.change(%{
          bucket_id: bucket.id,
          lookup_id: preview.lookup_id,
          to: preview.to,
          cc: preview.cc,
          subject: preview.subject,
          body: preview.body
        })
        |> Repo.insert()

        :ok

      {:error, _} ->
        :skipped
    end
  end

  defp sent_lookup_ids(bucket_id) do
    Repo.all(from m in Message, where: m.bucket_id == ^bucket_id, select: m.lookup_id)
    |> MapSet.new()
  end

  defp recipient(lookup) do
    best = lookup.brief && lookup.brief.best_contact

    cond do
      is_binary(best) and String.contains?(best, "@") -> best
      true -> Enum.find_value(lookup.contacts, &(&1.type == :email && &1.value))
    end
  end

  defp product_for(bucket, lookup) do
    brief_product = lookup.brief && lookup.brief.recommended_product
    brief_product || List.first(bucket.products || [])
  end

  defp fields(lookup, product) do
    %{
      "company" => lookup.company_name,
      "contact" => recipient(lookup) || "",
      "product" => (product && product.name) || "our service",
      "pitch" => (lookup.brief && lookup.brief.pitch) || ""
    }
  end

  defp fill(template, fields) do
    Enum.reduce(fields, template, fn {key, value}, text ->
      String.replace(text, "{{#{key}}}", value)
    end)
  end

  defp blank?(value), do: value in [nil, ""]
  defp present(value), do: if(blank?(value), do: nil, else: value)

  defp from_address do
    Application.get_env(:company_contact_finder, :outreach, [])
    |> Keyword.get(:from, {"GS1 Kenya Lead Finder", "leads@example.com"})
  end

  defp opt_out, do: "\n\n---\nReply stop if you do not want these emails."

  defp email_schema do
    %{
      name: "campaign_email",
      schema: %{
        type: "object",
        additionalProperties: false,
        required: ["subject", "body"],
        properties: %{
          subject: %{type: "string"},
          body: %{type: "string"}
        }
      }
    }
  end
end
