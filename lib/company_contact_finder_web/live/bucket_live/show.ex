defmodule CompanyContactFinderWeb.BucketLive.Show do
  use CompanyContactFinderWeb, :live_view

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Pipeline

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:buckets}>
      <div class="space-y-6">
        <.link
          navigate={~p"/buckets"}
          class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-gs1-blue dark:hover:text-white"
        >
          <.icon name="hero-arrow-left" class="size-4" /> All buckets
        </.link>

        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div class="min-w-0">
            <h1
              id="bucket-name"
              class="text-2xl font-bold tracking-tight text-gs1-blue dark:text-white sm:text-3xl"
            >
              {@bucket.name}
            </h1>
            <div class="mt-2 flex flex-wrap gap-1.5">
              <p
                :for={service <- @bucket.services}
                class="inline-flex items-center gap-1.5 rounded-md bg-gs1-orange/10 px-2 py-1 text-sm font-semibold text-gs1-orange-dark"
              >
                <.icon name="hero-tag" class="size-4" /> {service}
              </p>
            </div>
          </div>
          <div class="flex shrink-0 flex-wrap items-center gap-2">
            <.brand_button
              id="discover-companies"
              type="button"
              phx-click="discover"
              disabled={@discovery == :loading}
            >
              <.icon name="hero-sparkles" class="size-4" /> Find companies online
            </.brand_button>
            <.brand_button variant="outline" navigate={~p"/buckets/#{@bucket}/edit"} id="edit-bucket">
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.brand_button>
            <.brand_button
              variant="secondary"
              href={~p"/buckets/#{@bucket}/export.csv"}
              id="export-bucket"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV
            </.brand_button>
          </div>
        </div>

        <.discovery_panel :if={@discovery} discovery={@discovery} />

        <div class="grid gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
          <div class="space-y-6">
            <.card class="space-y-4 p-6" id="bucket-criteria">
              <h2 class="text-sm font-bold uppercase tracking-wide text-base-content/50">
                Leads we want
              </h2>
              <p class="leading-relaxed">{@bucket.target_description}</p>
              <dl class="space-y-3 text-sm">
                <.criterion :if={@bucket.industries != []} label="Industries">
                  {Enum.join(@bucket.industries, " · ")}
                </.criterion>
                <.criterion :if={@bucket.locations != []} label="Locations">
                  {Enum.join(@bucket.locations, " · ")}
                </.criterion>
                <.criterion :if={@bucket.company_sizes != []} label="Sizes">
                  <span class="capitalize">{Enum.join(@bucket.company_sizes, " · ")}</span>
                </.criterion>
                <.criterion :if={@bucket.disqualifiers} label="Not a fit">
                  {@bucket.disqualifiers}
                </.criterion>
                <.criterion :if={@bucket.service_details} label="Our offer">
                  {@bucket.service_details}
                </.criterion>
              </dl>
            </.card>

            <.card class="p-6">
              <h2 class="mb-1 text-base font-bold text-gs1-blue dark:text-white">Add companies</h2>
              <p class="mb-4 text-sm text-base-content/60">
                One per line. Each is searched, crawled and scored against this bucket.
              </p>
              <.form for={@add_form} id="add-companies-form" phx-submit="add" class="space-y-3">
                <textarea
                  id="add-names"
                  name="add[names]"
                  rows="5"
                  placeholder="Acme Foods&#10;Globex Kenya"
                  class={field_class()}
                >{@add_form[:names].value}</textarea>
                <div class="flex justify-end">
                  <.brand_button type="submit" id="add-companies-button">
                    <.icon name="hero-plus" class="size-4" /> Find & score
                  </.brand_button>
                </div>
              </.form>
            </.card>

            <div class="flex justify-end">
              <button
                id="delete-bucket"
                type="button"
                phx-click="delete"
                data-confirm="Delete this bucket? Its leads are kept, without a bucket."
                class="text-xs font-medium text-base-content/50 transition hover:text-red-600"
              >
                Delete bucket
              </button>
            </div>
          </div>

          <.card class="overflow-hidden">
            <div class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-5 py-4">
              <div>
                <h2 class="text-base font-bold text-gs1-blue dark:text-white">Ranked leads</h2>
                <p class="text-xs text-base-content/50">
                  {@lead_count} leads · {@strong_count} strong fits
                </p>
              </div>
              <.brand_button
                :if={@lead_count > 0}
                id="rescore-all"
                type="button"
                variant={if @stale_count > 0, do: "primary", else: "outline"}
                size="sm"
                phx-click="rescore"
                data-confirm={"Rescore #{@lead_count} leads with OpenAI?"}
              >
                <.icon name="hero-arrow-path" class="size-3.5" />
                {if @stale_count > 0, do: "Rescore #{@stale_count} outdated", else: "Rescore all"}
              </.brand_button>
            </div>

            <ol id="bucket-leads" phx-update="stream" class="divide-y divide-base-300">
              <li
                id="bucket-leads-empty"
                class="hidden flex-col items-center gap-2 px-6 py-14 text-center only:flex"
              >
                <.icon name="hero-inbox" class="size-8 text-base-content/30" />
                <p class="font-semibold">No leads in this bucket yet</p>
                <p class="text-sm text-base-content/50">Add companies to find and score them.</p>
              </li>
              <li :for={{dom_id, lookup} <- @streams.leads} id={dom_id}>
                <.link
                  navigate={~p"/lookups/#{lookup}"}
                  class="group flex items-start gap-4 px-5 py-4 transition hover:bg-gs1-blue/3"
                >
                  <.lead_score score={lookup.brief && lookup.brief.lead_score} />
                  <div class="min-w-0 flex-1 space-y-1">
                    <div class="flex flex-wrap items-center gap-2">
                      <p class="truncate font-semibold group-hover:text-gs1-blue dark:group-hover:text-gs1-orange">
                        {lookup.company_name}
                      </p>
                      <.fit_badge fit={lookup.brief && lookup.brief.fit} />
                      <span
                        :if={Leads.brief_stale?(lookup)}
                        title="Scored before the criteria changed"
                        class="inline-flex items-center gap-1 text-[11px] font-medium text-gs1-orange"
                      >
                        <.icon name="hero-exclamation-circle" class="size-3.5" /> Outdated
                      </span>
                    </div>
                    <p
                      :if={lookup.brief && lookup.brief.fit_reason}
                      class="line-clamp-2 text-sm text-base-content/60"
                    >
                      {lookup.brief.fit_reason}
                    </p>
                    <p class="text-xs text-base-content/40">
                      {display_host(lookup.website_url) || "No website yet"} · {lookup.contact_count ||
                        0} contacts
                    </p>
                  </div>
                  <.status_badge :if={lookup.status != :done} status={lookup.status} />
                </.link>
              </li>
            </ol>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :discovery, :any, required: true

  defp discovery_panel(%{discovery: :loading} = assigns) do
    ~H"""
    <.card id="discovery" class="flex items-center gap-3 p-6">
      <.icon name="hero-arrow-path" class="size-5 text-gs1-orange motion-safe:animate-spin" />
      <div>
        <p class="font-semibold">Searching online...</p>
        <p class="text-sm text-base-content/60">
          Looking for rankings, lists and directories, then reading them for company names.
          This takes up to a minute.
        </p>
      </div>
    </.card>
    """
  end

  defp discovery_panel(%{discovery: {:error, _message}} = assigns) do
    ~H"""
    <.card id="discovery" class="flex items-start justify-between gap-3 p-6">
      <div>
        <p class="font-semibold text-red-600">Couldn't search for companies</p>
        <p class="text-sm text-base-content/60">{elem(@discovery, 1)}</p>
      </div>
      <button type="button" phx-click="close_discovery" class="text-base-content/50">
        <.icon name="hero-x-mark" class="size-5" />
      </button>
    </.card>
    """
  end

  defp discovery_panel(%{discovery: {:ok, %{queries: _, suggestions: _}}} = assigns) do
    assigns = assign(assigns, elem(assigns.discovery, 1))

    ~H"""
    <.card id="discovery" class="overflow-hidden">
      <div class="flex items-start justify-between gap-3 border-b border-base-300 px-5 py-4">
        <div>
          <h2 class="text-base font-bold text-gs1-blue dark:text-white">Companies found online</h2>
          <p class="text-xs text-base-content/50">
            Searched: {Enum.map_join(@queries, " · ", &"“#{&1}”")}
          </p>
        </div>
        <button
          type="button"
          phx-click="close_discovery"
          class="text-base-content/50"
          aria-label="Close"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <p :if={@suggestions == []} id="discovery-empty" class="px-5 py-10 text-center text-sm">
        No new companies found. Try adding industries or locations to the bucket.
      </p>

      <.form
        :if={@suggestions != []}
        for={%{}}
        as={:pick}
        id="discovery-form"
        phx-submit="add_suggestions"
      >
        <ul class="max-h-[28rem] divide-y divide-base-300 overflow-y-auto">
          <li :for={{suggestion, index} <- Enum.with_index(@suggestions)}>
            <label
              for={"suggestion-#{index}"}
              class="flex cursor-pointer items-start gap-3 px-5 py-3 transition hover:bg-gs1-blue/3"
            >
              <input
                type="checkbox"
                id={"suggestion-#{index}"}
                name="pick[names][]"
                value={suggestion.name}
                class="checkbox checkbox-sm mt-0.5"
              />
              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center gap-2">
                  <span class="font-semibold">{suggestion.name}</span>
                  <span class={[
                    "rounded-full px-2 py-0.5 text-[11px] font-semibold",
                    if(suggestion.fit == "strong",
                      do: "bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300",
                      else: "bg-base-200 text-base-content/60"
                    )
                  ]}>
                    {if suggestion.fit == "strong", do: "Strong match", else: "Possible"}
                  </span>
                </div>
                <p :if={suggestion.reason} class="text-sm text-base-content/60">
                  {suggestion.reason}
                </p>
                <a
                  :if={suggestion.source_url}
                  href={suggestion.source_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-xs text-base-content/40 hover:text-gs1-blue hover:underline"
                >
                  {display_host(suggestion.source_url)}
                </a>
              </div>
            </label>
          </li>
        </ul>
        <div class="flex items-center justify-between gap-3 border-t border-base-300 px-5 py-3">
          <p class="text-xs text-base-content/50">
            {length(@suggestions)} companies. Tick the ones to find, crawl and score.
          </p>
          <.brand_button type="submit" id="add-suggestions" size="sm">
            <.icon name="hero-plus" class="size-3.5" /> Add selected
          </.brand_button>
        </div>
      </.form>
    </.card>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp criterion(assigns) do
    ~H"""
    <div>
      <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/50">{@label}</dt>
      <dd class="mt-0.5">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    bucket = Leads.get_bucket!(id)

    if connected?(socket) do
      Leads.subscribe_lookups()
      Leads.subscribe_buckets()
    end

    {:ok,
     socket
     |> assign(:bucket, bucket)
     |> assign(:page_title, bucket.name)
     |> assign(:add_form, to_form(%{"names" => ""}, as: :add))
     |> assign(:discovery, nil)
     |> load_leads()}
  end

  defp load_leads(socket) do
    bucket = socket.assigns.bucket

    leads =
      [bucket_id: bucket.id, sort: :score, limit: 500]
      |> Leads.list_lookups()
      |> Enum.map(&%{&1 | bucket: bucket})

    socket
    |> assign(:lead_ids, MapSet.new(leads, & &1.id))
    |> assign(:lead_count, length(leads))
    |> assign(:strong_count, Enum.count(leads, &(&1.brief && &1.brief.fit == "strong")))
    |> assign(:stale_count, Enum.count(leads, &Leads.brief_stale?/1))
    |> stream(:leads, leads, reset: true)
  end

  @impl true
  def handle_event("add", %{"add" => %{"names" => names}}, socket) do
    case Leads.start_bulk_lookups(names, socket.assigns.bucket.id) do
      {:ok, []} ->
        {:noreply, put_flash(socket, :error, "Add at least one company name (2+ characters).")}

      {:ok, lookups} ->
        {:noreply,
         socket
         |> put_flash(:info, "Finding and scoring #{length(lookups)} companies.")
         |> assign(:add_form, to_form(%{"names" => ""}, as: :add))
         |> load_leads()}
    end
  end

  def handle_event("discover", _params, socket) do
    bucket = socket.assigns.bucket

    {:noreply,
     socket
     |> assign(:discovery, :loading)
     |> start_async(:discover, fn -> Leads.discover_companies(bucket) end)}
  end

  def handle_event("close_discovery", _params, socket) do
    {:noreply, socket |> cancel_async(:discover) |> assign(:discovery, nil)}
  end

  def handle_event("add_suggestions", params, socket) do
    names = get_in(params, ["pick", "names"]) || []

    case Leads.start_bulk_lookups(Enum.join(names, "\n"), socket.assigns.bucket.id) do
      {:ok, []} ->
        {:noreply, put_flash(socket, :error, "Tick at least one company to add.")}

      {:ok, lookups} ->
        {:ok, result} = socket.assigns.discovery
        added = MapSet.new(lookups, &String.downcase(&1.company_name))
        remaining = Enum.reject(result.suggestions, &(String.downcase(&1.name) in added))

        {:noreply,
         socket
         |> put_flash(:info, "Finding and scoring #{length(lookups)} companies.")
         |> assign(:discovery, {:ok, %{result | suggestions: remaining}})
         |> load_leads()}
    end
  end

  def handle_event("rescore", _params, socket) do
    {:ok, count} = Leads.rescore_bucket(socket.assigns.bucket)
    {:noreply, put_flash(socket, :info, "Rescoring #{count} leads.")}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Leads.delete_bucket(socket.assigns.bucket)

    {:noreply,
     socket
     |> put_flash(:info, "Bucket deleted.")
     |> push_navigate(to: ~p"/buckets")}
  end

  @impl true
  def handle_async(:discover, {:ok, {:ok, result}}, socket),
    do: {:noreply, assign(socket, :discovery, {:ok, result})}

  def handle_async(:discover, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, :discovery, {:error, Pipeline.describe(reason)})}

  def handle_async(:discover, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, :discovery, {:error, Pipeline.describe(:unexpected_error)})}

  @impl true
  def handle_info({:lookup_updated, lookup}, socket) do
    # Refresh when a lead in (or just moved out of) this bucket changes.
    if lookup.bucket_id == socket.assigns.bucket.id or lookup.id in socket.assigns.lead_ids,
      do: {:noreply, load_leads(socket)},
      else: {:noreply, socket}
  end

  def handle_info(
        {:bucket_updated, %{id: id} = bucket},
        %{assigns: %{bucket: %{id: id}}} = socket
      ) do
    {:noreply,
     socket |> assign(:bucket, bucket) |> assign(:page_title, bucket.name) |> load_leads()}
  end

  def handle_info({:bucket_deleted, %{id: id}}, %{assigns: %{bucket: %{id: id}}} = socket) do
    {:noreply,
     socket |> put_flash(:info, "This bucket was deleted.") |> push_navigate(to: ~p"/buckets")}
  end

  def handle_info({event, _bucket}, socket) when event in [:bucket_updated, :bucket_deleted],
    do: {:noreply, socket}
end
