defmodule CompanyContactFinderWeb.LookupLive.Show do
  use CompanyContactFinderWeb, :live_view

  alias CompanyContactFinder.Leads

  @steps [searching: "Search", crawling: "Crawl", analysing: "Analyse", done: "Done"]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <.link
          navigate={~p"/"}
          class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-base-content"
        >
          <.icon name="hero-arrow-left" class="size-4" /> All lookups
        </.link>

        <%!-- Header --%>
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div class="min-w-0 space-y-2">
            <div class="flex flex-wrap items-center gap-3">
              <h1
                id="company-name"
                class="truncate text-2xl font-bold tracking-tight text-gs1-blue dark:text-white sm:text-3xl"
              >
                {@lookup.company_name}
              </h1>
              <.status_badge id="lookup-status" status={@lookup.status} />
            </div>
            <p
              :if={@lookup.website_url}
              class="flex items-center gap-1.5 text-sm text-base-content/60"
            >
              <.icon name="hero-globe-alt" class="size-4" />
              <.external_link
                href={@lookup.website_url}
                class="font-medium text-base-content/80 underline-offset-4 hover:text-gs1-blue dark:hover:text-gs1-orange hover:underline"
              >
                {display_host(@lookup.website_url)}
              </.external_link>
              <span
                :if={@lookup.source == :listing}
                id="listing-badge"
                class="rounded bg-base-200 px-1.5 py-0.5 text-xs text-base-content/60"
              >
                Directory listing
              </span>
              <span :if={@lookup.website_overridden} class="text-xs text-base-content/40">
                (set manually)
              </span>
              <span :if={@lookup.pages_crawled > 0} class="text-xs text-base-content/40">
                · {@lookup.pages_crawled} {if @lookup.pages_crawled == 1, do: "page", else: "pages"} crawled
              </span>
            </p>
          </div>

          <div class="flex shrink-0 items-center gap-2">
            <.brand_button
              id="rerun-button"
              type="button"
              variant="outline"
              phx-click="rerun"
              disabled={@busy?}
            >
              <.icon name="hero-arrow-path" class="size-4" /> Re-run
            </.brand_button>
            <.brand_button
              id="export-link"
              variant="secondary"
              href={~p"/lookups/#{@lookup}/export.csv"}
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV
            </.brand_button>
          </div>
        </div>

        <%!-- Progress --%>
        <.card :if={@lookup.status != :done} class="p-5">
          <div
            :if={@lookup.status == :failed}
            id="lookup-error"
            class="flex items-start gap-3 text-red-700 dark:text-red-400"
          >
            <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 shrink-0" />
            <div>
              <p class="font-medium">This lookup failed</p>
              <p class="text-sm opacity-80">{@lookup.error}</p>
            </div>
          </div>
          <ol :if={@lookup.status != :failed} id="progress-steps" class="flex items-center gap-2">
            <li
              :for={{{step, label}, index} <- Enum.with_index(@steps)}
              class="flex flex-1 items-center gap-2"
            >
              <span class={[
                "grid size-7 shrink-0 place-items-center rounded-full text-xs font-semibold transition",
                step_state(@lookup.status, step) == :done && "bg-gs1-blue text-white",
                step_state(@lookup.status, step) == :active &&
                  "bg-gs1-orange text-white ring-4 ring-gs1-orange/20 motion-safe:animate-pulse",
                step_state(@lookup.status, step) == :todo && "bg-base-200 text-base-content/50"
              ]}>
                <.icon
                  :if={step_state(@lookup.status, step) == :done}
                  name="hero-check-mini"
                  class="size-4"
                />
                <span :if={step_state(@lookup.status, step) != :done}>{index + 1}</span>
              </span>
              <span class="hidden text-sm font-medium sm:inline">{label}</span>
              <span :if={index < length(@steps) - 1} class="h-px flex-1 bg-base-300" />
            </li>
          </ol>
        </.card>

        <div class="grid gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
          <div class="space-y-6">
            <%!-- AI brief --%>
            <.card id="brief-card" class="p-6">
              <div class="mb-4 flex items-center justify-between gap-3">
                <h2 class="flex items-center gap-2 text-base font-semibold">
                  <.icon name="hero-sparkles" class="size-5 text-gs1-orange" /> Company brief
                </h2>
                <span class="rounded-full bg-base-200 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wide text-base-content/50">
                  AI-generated
                </span>
              </div>

              <%= cond do %>
                <% @brief && @brief.status == :done -> %>
                  <div id="brief" class="space-y-5">
                    <div
                      :if={@stale?}
                      id="brief-stale"
                      class="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-gs1-orange/30 bg-gs1-orange/5 px-3 py-2 text-sm"
                    >
                      <span class="flex items-center gap-1.5">
                        <.icon name="hero-exclamation-circle" class="size-4 text-gs1-orange" />
                        Scored before this bucket's criteria changed.
                      </span>
                      <.brand_button
                        id="rescore-button"
                        type="button"
                        size="sm"
                        phx-click="retry_brief"
                        disabled={@busy?}
                      >
                        Rescore
                      </.brand_button>
                    </div>

                    <div class="flex items-start gap-4">
                      <.lead_score score={@brief.lead_score} size="lg" />
                      <div class="min-w-0 space-y-1">
                        <div class="flex flex-wrap items-center gap-2">
                          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                            {if @bucket, do: "Score for #{@bucket.name}", else: "Lead score"}
                          </p>
                          <.fit_badge :if={@bucket} id="brief-fit" fit={@brief.fit} />
                        </div>
                        <p class="text-sm text-base-content/80">
                          {(@bucket && @brief.fit_reason) || @brief.lead_score_reason}
                        </p>
                      </div>
                    </div>

                    <p :if={@brief.summary} class="leading-relaxed">{@brief.summary}</p>

                    <dl class="grid gap-4 sm:grid-cols-2">
                      <.fact :if={@brief.industry} label="Industry">{@brief.industry}</.fact>
                      <.fact
                        :if={@brief.company_size_hint && @brief.company_size_hint != "unknown"}
                        label="Size"
                      >
                        {String.capitalize(@brief.company_size_hint)}
                      </.fact>
                      <.fact :if={@brief.locations != []} label="Locations">
                        {Enum.join(@brief.locations, " · ")}
                      </.fact>
                      <.fact :if={@brief.target_customers} label="Customers">
                        {@brief.target_customers}
                      </.fact>
                    </dl>

                    <div :if={@brief.products_services != []}>
                      <p class="mb-2 text-xs font-medium uppercase tracking-wide text-base-content/50">
                        Products & services
                      </p>
                      <div class="flex flex-wrap gap-1.5">
                        <span
                          :for={item <- @brief.products_services}
                          class="rounded-md bg-base-200 px-2 py-1 text-xs font-medium"
                        >
                          {item}
                        </span>
                      </div>
                    </div>

                    <div
                      :if={@brief.pitch || @brief.outreach_angle || @brief.best_contact}
                      class="space-y-2 rounded-xl border-l-4 border-gs1-orange bg-gs1-blue/5 p-4 dark:bg-white/5"
                    >
                      <p :if={@brief.pitch} id="brief-pitch" class="text-sm">
                        <span class="font-semibold text-gs1-blue dark:text-white">
                          How to pitch {(@bucket && Enum.join(@bucket.services, ", ")) || "GS1 Kenya"}:
                        </span>
                        {@brief.pitch}
                      </p>
                      <p :if={@brief.best_contact} class="text-sm">
                        <span class="font-medium">Best contact:</span> {@brief.best_contact}
                      </p>
                      <p :if={@brief.outreach_angle} class="text-sm">
                        <span class="font-medium">Outreach angle:</span> {@brief.outreach_angle}
                      </p>
                    </div>

                    <p :if={@brief.model} class="text-[11px] text-base-content/40">
                      {@brief.model} · {(@brief.prompt_tokens || 0) + (@brief.completion_tokens || 0)} tokens
                    </p>
                  </div>
                <% @brief && @brief.status == :failed -> %>
                  <div id="brief-failed" class="flex flex-col items-start gap-3">
                    <p class="text-sm text-base-content/70">
                      Couldn't generate a brief: {@brief.error}
                    </p>
                    <.brand_button
                      id="retry-brief-button"
                      type="button"
                      variant="outline"
                      size="sm"
                      phx-click="retry_brief"
                      disabled={@busy?}
                    >
                      <.icon name="hero-arrow-path" class="size-4" /> Retry brief
                    </.brand_button>
                  </div>
                <% @lookup.status == :failed -> %>
                  <p class="text-sm text-base-content/50">No brief. The lookup didn't finish.</p>
                <% true -> %>
                  <div id="brief-loading" class="space-y-3" aria-busy="true">
                    <div class="h-4 w-3/4 rounded bg-base-200 motion-safe:animate-pulse" />
                    <div class="h-4 w-full rounded bg-base-200 motion-safe:animate-pulse" />
                    <div class="h-4 w-5/6 rounded bg-base-200 motion-safe:animate-pulse" />
                  </div>
              <% end %>
            </.card>

            <%!-- Lead bucket --%>
            <.card class="p-6">
              <h2 class="mb-1 text-base font-bold text-gs1-blue dark:text-white">Lead bucket</h2>
              <p class="mb-4 text-sm text-base-content/60">
                The brief is scored against the bucket's target leads and service. Changing it
                rescores this lead.
              </p>
              <form id="bucket-form" phx-change="assign_bucket" class="flex items-center gap-2">
                <select name="bucket_id" class={field_class()} disabled={@busy?}>
                  <option value="">No bucket (general score)</option>
                  {Phoenix.HTML.Form.options_for_select(@bucket_options, @lookup.bucket_id)}
                </select>
                <.brand_button
                  :if={@bucket}
                  variant="ghost"
                  size="sm"
                  navigate={~p"/buckets/#{@bucket}"}
                  class="shrink-0"
                >
                  Open <.icon name="hero-arrow-right" class="size-3.5" />
                </.brand_button>
              </form>
            </.card>

            <%!-- Website override --%>
            <.card class="p-6">
              <h2 class="mb-1 text-base font-semibold">Wrong website?</h2>
              <p class="mb-4 text-sm text-base-content/60">
                Set the right one and we'll crawl it instead. No website? Paste the
                company's page on a directory like Yellow Pages Kenya.
              </p>
              <.form
                for={@website_form}
                id="website-form"
                phx-submit="set_website"
                class="flex flex-col gap-2 sm:flex-row sm:items-start"
              >
                <div class="flex-1">
                  <.input
                    field={@website_form[:website_url]}
                    type="text"
                    placeholder="https://example.com"
                    class={field_class()}
                  />
                </div>
                <.brand_button type="submit" variant="secondary" disabled={@busy?}>
                  Crawl this site
                </.brand_button>
              </.form>

              <div :if={length(@lookup.candidates) > 1} class="mt-5">
                <p class="mb-2 text-xs font-medium uppercase tracking-wide text-base-content/50">
                  Other search results
                </p>
                <ul id="candidates" class="divide-y divide-base-300 rounded-lg border border-base-300">
                  <li
                    :for={{candidate, i} <- Enum.with_index(@lookup.candidates)}
                    id={"candidate-#{i}"}
                    class="flex items-center justify-between gap-3 px-3 py-2"
                  >
                    <div class="min-w-0">
                      <p class="truncate text-sm font-medium">{candidate["host"]}</p>
                      <p :if={candidate["title"]} class="truncate text-xs text-base-content/50">
                        {candidate["title"]}
                      </p>
                    </div>
                    <span
                      :if={candidate["url"] == @lookup.website_url}
                      class="shrink-0 text-xs font-medium text-emerald-600"
                    >
                      In use
                    </span>
                    <button
                      :if={candidate["url"] != @lookup.website_url}
                      type="button"
                      phx-click="use_candidate"
                      phx-value-url={candidate["url"]}
                      disabled={@busy?}
                      class="shrink-0 rounded-md px-2 py-1 text-xs font-semibold text-gs1-orange transition hover:bg-gs1-orange/10 disabled:opacity-50"
                    >
                      Use this
                    </button>
                  </li>
                </ul>
              </div>
            </.card>
          </div>

          <%!-- Contacts --%>
          <div class="space-y-6">
            <.contact_group
              id="emails"
              title="Emails"
              icon="hero-envelope"
              count={MapSet.size(@contact_ids.email)}
              stream={@streams.emails}
              busy?={@busy?}
            />
            <.contact_group
              id="phones"
              title="Phone numbers"
              icon="hero-phone"
              count={MapSet.size(@contact_ids.phone)}
              stream={@streams.phones}
              busy?={@busy?}
            />
            <.contact_group
              id="socials"
              title="Social profiles"
              icon="hero-share"
              count={MapSet.size(@contact_ids.social)}
              stream={@streams.socials}
              busy?={@busy?}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp fact(assigns) do
    ~H"""
    <div>
      <dt class="text-xs font-medium uppercase tracking-wide text-base-content/50">{@label}</dt>
      <dd class="mt-0.5 text-sm">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :count, :integer, required: true
  attr :stream, :any, required: true
  attr :busy?, :boolean, required: true

  defp contact_group(assigns) do
    ~H"""
    <.card class="overflow-hidden">
      <div class="flex items-center justify-between border-b border-base-300 px-5 py-3">
        <h2 class="flex items-center gap-2 text-sm font-semibold">
          <.icon name={@icon} class="size-4 text-base-content/50" /> {@title}
        </h2>
        <span class="rounded-full bg-base-200 px-2 py-0.5 text-xs font-medium tabular-nums">
          {@count}
        </span>
      </div>
      <ul id={@id} phx-update="stream" class="divide-y divide-base-300">
        <li class="hidden px-5 py-6 text-center text-sm text-base-content/50 only:block">
          {if @busy?, do: "Looking…", else: "None found"}
        </li>
        <li :for={{dom_id, contact} <- @stream} id={dom_id} class="group px-5 py-3">
          <div class="flex items-center justify-between gap-3">
            <.contact_value contact={contact} />
            <div class="flex shrink-0 items-center gap-1.5">
              <span
                :if={contact.role}
                class="rounded-md bg-base-200 px-1.5 py-0.5 text-[11px] font-medium capitalize"
              >
                {contact.role}
              </span>
              <span
                :if={contact.quality}
                title="AI-rated quality"
                class={[
                  "size-2 rounded-full",
                  contact.quality == "high" && "bg-emerald-500",
                  contact.quality == "medium" && "bg-amber-500",
                  contact.quality == "low" && "bg-red-500"
                ]}
              />
            </div>
          </div>
          <p :if={contact.ai_note} class="mt-1 text-xs text-base-content/60">{contact.ai_note}</p>
          <.external_link
            href={contact.source_url}
            class="mt-1 block truncate text-[11px] text-base-content/40 transition hover:text-base-content/70"
          >
            Found on {source_path(contact.source_url)}
          </.external_link>
        </li>
      </ul>
    </.card>
    """
  end

  attr :contact, :any, required: true

  defp contact_value(%{contact: %{type: :email}} = assigns) do
    ~H"""
    <a
      href={"mailto:#{@contact.value}"}
      class="min-w-0 truncate font-medium transition hover:text-gs1-blue dark:hover:text-gs1-orange"
    >
      {@contact.value}
    </a>
    """
  end

  defp contact_value(%{contact: %{type: :phone}} = assigns) do
    ~H"""
    <a
      href={"tel:#{@contact.value}"}
      class="min-w-0 truncate font-medium tabular-nums transition hover:text-gs1-blue dark:hover:text-gs1-orange"
    >
      {@contact.value}
    </a>
    """
  end

  defp contact_value(assigns) do
    ~H"""
    <.external_link
      href={@contact.value}
      class="min-w-0 truncate font-medium transition hover:text-gs1-blue dark:hover:text-gs1-orange"
    >
      {String.replace(@contact.value, ~r/^https:\/\//, "")}
    </.external_link>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Subscribe before loading so no contacts are missed in between.
    if connected?(socket) do
      Leads.subscribe_lookup(id)
      Leads.subscribe_buckets()
    end

    lookup = Leads.get_lookup!(id)

    grouped = Enum.group_by(lookup.contacts, & &1.type)

    {:ok,
     socket
     |> assign(:page_title, lookup.company_name)
     |> assign(:steps, @steps)
     |> assign(:brief, lookup.brief)
     |> assign(:bucket, lookup.bucket)
     |> assign(:bucket_options, Leads.bucket_options())
     |> assign_lookup(lookup)
     |> assign(:website_form, to_form(Leads.change_website(lookup)))
     |> assign(:contact_ids, %{
       email: ids(grouped[:email]),
       phone: ids(grouped[:phone]),
       social: ids(grouped[:social])
     })
     |> stream(:emails, grouped[:email] || [])
     |> stream(:phones, grouped[:phone] || [])
     |> stream(:socials, grouped[:social] || [])}
  end

  defp assign_lookup(socket, lookup) do
    # Broadcasts may carry a lookup without its bucket loaded.
    bucket =
      case {lookup.bucket, socket.assigns[:bucket]} do
        {%CompanyContactFinder.Leads.Bucket{} = bucket, _} -> bucket
        {_, %{id: id} = bucket} when id == lookup.bucket_id -> bucket
        _ when is_nil(lookup.bucket_id) -> nil
        _ -> Leads.get_bucket!(lookup.bucket_id)
      end

    socket
    |> assign(:lookup, lookup)
    |> assign(:bucket, bucket)
    |> assign(:busy?, Leads.in_progress?(lookup))
    |> assign_stale()
  end

  defp assign_stale(socket) do
    %{lookup: lookup, brief: brief, bucket: bucket} = socket.assigns
    assign(socket, :stale?, Leads.brief_stale?(%{lookup | brief: brief, bucket: bucket}))
  end

  @impl true
  def handle_event("rerun", _params, socket) do
    socket.assigns.lookup |> Leads.rerun_lookup() |> after_rerun(socket)
  end

  def handle_event("retry_brief", _params, socket) do
    case Leads.retry_brief(socket.assigns.lookup) do
      :ok ->
        {:noreply, socket}

      {:error, :in_progress} ->
        {:noreply, put_flash(socket, :error, "This lookup is still running.")}
    end
  end

  def handle_event("assign_bucket", %{"bucket_id" => bucket_id}, socket) do
    case Leads.assign_bucket(socket.assigns.lookup, bucket_id) do
      {:ok, lookup} ->
        {:noreply, assign_lookup(socket, lookup)}

      {:error, :in_progress} ->
        {:noreply, put_flash(socket, :error, "This lookup is still running.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "That bucket no longer exists.")}
    end
  end

  def handle_event("set_website", %{"lookup" => params}, socket) do
    socket.assigns.lookup |> Leads.rerun_with_website(params) |> after_rerun(socket)
  end

  def handle_event("use_candidate", %{"url" => url}, socket) do
    socket.assigns.lookup
    |> Leads.rerun_with_website(%{"website_url" => url})
    |> after_rerun(socket)
  end

  defp after_rerun({:ok, lookup}, socket) do
    {:noreply,
     socket
     |> assign_lookup(lookup)
     |> assign(:brief, nil)
     |> assign(:contact_ids, %{email: MapSet.new(), phone: MapSet.new(), social: MapSet.new()})
     |> assign(:website_form, to_form(Leads.change_website(lookup)))
     |> stream(:emails, [], reset: true)
     |> stream(:phones, [], reset: true)
     |> stream(:socials, [], reset: true)}
  end

  defp after_rerun({:error, :in_progress}, socket),
    do: {:noreply, put_flash(socket, :error, "This lookup is still running.")}

  defp after_rerun({:error, %Ecto.Changeset{} = changeset}, socket),
    do: {:noreply, assign(socket, :website_form, to_form(changeset, action: :update))}

  @impl true
  def handle_info({:lookup_updated, lookup}, socket) do
    {:noreply, assign_lookup(socket, lookup)}
  end

  def handle_info({:brief_updated, brief}, socket) do
    {:noreply, socket |> assign(:brief, brief) |> assign_stale()}
  end

  def handle_info({:bucket_updated, bucket}, socket) do
    socket = assign(socket, :bucket_options, Leads.bucket_options())

    socket =
      if socket.assigns.lookup.bucket_id == bucket.id,
        do: socket |> assign(:bucket, bucket) |> assign_stale(),
        else: socket

    {:noreply, socket}
  end

  def handle_info({:bucket_deleted, _bucket}, socket) do
    lookup = Leads.get_lookup!(socket.assigns.lookup.id)
    {:noreply, socket |> assign(:bucket_options, Leads.bucket_options()) |> assign_lookup(lookup)}
  end

  def handle_info({:contacts_added, contacts}, socket) do
    socket =
      Enum.reduce(contacts, socket, fn contact, socket ->
        socket
        |> update(
          :contact_ids,
          &Map.update!(&1, contact.type, fn ids -> MapSet.put(ids, contact.id) end)
        )
        |> stream_insert(stream_name(contact), contact)
      end)

    {:noreply, socket}
  end

  def handle_info({:contacts_updated, contacts}, socket) do
    {:noreply, Enum.reduce(contacts, socket, &stream_insert(&2, stream_name(&1), &1))}
  end

  defp ids(nil), do: MapSet.new()
  defp ids(contacts), do: MapSet.new(contacts, & &1.id)

  defp stream_name(%{type: :email}), do: :emails
  defp stream_name(%{type: :phone}), do: :phones
  defp stream_name(%{type: :social}), do: :socials

  defp step_state(:done, _step), do: :done

  defp step_state(status, step) do
    order = Keyword.keys(@steps)
    current = Enum.find_index(order, &(&1 == status)) || -1
    index = Enum.find_index(order, &(&1 == step))

    cond do
      index < current -> :done
      index == current -> :active
      true -> :todo
    end
  end

  defp source_path(url) do
    case URI.parse(url || "") do
      %URI{path: path} when path not in [nil, "", "/"] -> path
      _ -> "homepage"
    end
  end
end
