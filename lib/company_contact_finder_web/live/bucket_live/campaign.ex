defmodule CompanyContactFinderWeb.BucketLive.Campaign do
  use CompanyContactFinderWeb, :live_view

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Bucket
  alias CompanyContactFinder.Outreach

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:buckets}>
      <div class="space-y-6">
        <.link
          navigate={~p"/buckets/#{@bucket}"}
          class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-gs1-blue"
        >
          <.icon name="hero-arrow-left" class="size-4" /> {@bucket.name}
        </.link>

        <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h1 class="text-2xl font-bold tracking-tight text-gs1-blue sm:text-3xl">
              Campaign preview
            </h1>
            <p class="mt-1 max-w-xl text-sm text-base-content/60">
              These drafts are not sent until you fire the campaign.
            </p>
          </div>
          <.brand_button
            id="fire-campaign"
            type="button"
            phx-click="fire"
            data-confirm="Send this campaign to every lead in the preview that has not already been emailed?"
            disabled={@ready_count == 0}
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Fire campaign
          </.brand_button>
        </div>

        <.form
          for={@form}
          id="campaign-form"
          phx-change="save"
          class="space-y-4"
        >
          <.card class="space-y-4 p-6">
            <.input
              field={@form[:email_mode]}
              type="select"
              label="Email style"
              options={[{"Same text, names swapped in", "static"}, {"Written per lead", "dynamic"}]}
            />
            <.input
              :if={@bucket.email_mode != "dynamic"}
              field={@form[:email_subject]}
              type="text"
              label="Subject"
              placeholder="{{product}} for {{company}}"
            />
            <.input
              :if={@bucket.email_mode != "dynamic"}
              field={@form[:email_template]}
              type="textarea"
              rows="8"
              label="Body"
              placeholder="Use {{company}}, {{contact}}, {{product}}, and {{pitch}}"
            />
            <.input
              :if={@bucket.email_mode == "dynamic"}
              field={@form[:email_prompt]}
              type="textarea"
              rows="6"
              label="Prompt"
              placeholder="Keep the first sentence about what they sell. Use one proof point. Ask for a reply, not a call."
            />
          </.card>
        </.form>

        <p id="campaign-count" class="text-sm text-base-content/60">
          {@ready_count} ready to send · {length(@previews)} leads in this preview
        </p>

        <div id="campaign-previews" class="space-y-4">
          <p :if={@previews == []} class="text-sm text-base-content/50">
            No finished leads in this bucket yet.
          </p>
          <.card :for={preview <- @previews} id={"preview-#{preview.lookup_id}"} class="space-y-2 p-6">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h2 class="font-semibold text-gs1-blue">{preview.company}</h2>
              <span :if={preview.sent?} class="text-xs font-medium text-base-content/50">
                Already sent
              </span>
              <span :if={preview.error} class="text-xs font-medium text-gs1-orange">
                {preview.error}
              </span>
            </div>
            <p :if={preview.to} class="text-sm text-base-content/70">
              To {preview.to}<span :if={preview.cc}> · CC {preview.cc}</span>
            </p>
            <p :if={preview.subject} class="text-sm font-medium">{preview.subject}</p>
            <pre
              :if={preview.body}
              class="whitespace-pre-wrap font-sans text-sm text-base-content/80"
            >{preview.body}</pre>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    bucket = Leads.get_bucket!(id)

    {:ok,
     socket
     |> assign(:page_title, "Campaign preview")
     |> assign(:bucket, bucket)
     |> assign_previews()
     |> assign_form(bucket)}
  end

  @impl true
  def handle_event("save", %{"bucket" => params}, socket) do
    case Leads.update_campaign(socket.assigns.bucket, params) do
      {:ok, bucket} ->
        {:noreply, socket |> assign(:bucket, bucket) |> assign_previews() |> assign_form(bucket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("fire", _params, socket) do
    %{sent: sent, skipped: skipped} =
      Outreach.fire(socket.assigns.bucket, socket.assigns.previews)

    {:noreply,
     socket
     |> assign_previews()
     |> put_flash(:info, "Campaign fired. Sent #{sent}. Skipped #{skipped}.")}
  end

  defp assign_previews(socket) do
    bucket = socket.assigns.bucket
    previews = bucket |> Outreach.campaign_leads() |> then(&Outreach.preview(bucket, &1))
    ready = Enum.count(previews, &ready?/1)

    socket
    |> assign(:previews, previews)
    |> assign(:ready_count, ready)
  end

  defp assign_form(socket, bucket) do
    assign(socket, :form, to_form(Bucket.campaign_changeset(bucket, %{})))
  end

  defp ready?(preview) do
    not preview.sent? and is_nil(preview.error) and preview.to not in [nil, ""]
  end
end
