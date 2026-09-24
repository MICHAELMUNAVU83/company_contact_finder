defmodule CompanyContactFinderWeb.BucketLive.Index do
  use CompanyContactFinderWeb, :live_view

  alias CompanyContactFinder.Leads

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:buckets}>
      <div class="space-y-8">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold tracking-tight text-gs1-blue dark:text-white sm:text-3xl">
              Lead buckets
            </h1>
            <p class="mt-1 max-w-xl text-sm text-base-content/60">
              A bucket says which companies you want and what GS1 Kenya service you'll
              offer them. Leads in a bucket are scored on how well they fit.
            </p>
          </div>
          <.brand_button navigate={~p"/buckets/new"} id="new-bucket">
            <.icon name="hero-plus" class="size-4" /> New bucket
          </.brand_button>
        </div>

        <div id="buckets" phx-update="stream" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div
            id="buckets-empty"
            class="hidden flex-col items-center gap-3 rounded-2xl border-2 border-dashed border-base-300 px-6 py-16 text-center only:flex sm:col-span-2 lg:col-span-3"
          >
            <span class="grid size-12 place-items-center rounded-2xl bg-gs1-orange/10 text-gs1-orange">
              <.icon name="hero-rectangle-stack" class="size-6" />
            </span>
            <p class="font-semibold">No buckets yet</p>
            <p class="max-w-sm text-sm text-base-content/50">
              For example: "Nairobi food manufacturers" offered GS1 barcodes, or
              "Pharma distributors" offered traceability.
            </p>
            <.brand_button navigate={~p"/buckets/new"} variant="secondary" size="sm">
              Create your first bucket
            </.brand_button>
          </div>

          <.link
            :for={{dom_id, bucket} <- @streams.buckets}
            id={dom_id}
            navigate={~p"/buckets/#{bucket}"}
            class="group flex flex-col rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-gs1-blue/30 hover:shadow-md"
          >
            <div class="mb-3 h-1 w-10 rounded-full bg-gs1-orange transition-all group-hover:w-16" />
            <h2 class="text-base font-bold text-gs1-blue dark:text-white">{bucket.name}</h2>
            <p class="mt-1 line-clamp-2 text-sm text-base-content/60">{bucket.target_description}</p>
            <div class="mt-3 flex flex-wrap gap-1">
              <p
                :for={service <- bucket.services}
                class="inline-flex w-fit items-center gap-1 rounded-md bg-gs1-blue/5 px-2 py-1 text-xs font-medium text-gs1-blue dark:bg-white/10 dark:text-white"
              >
                <.icon name="hero-tag" class="size-3.5" /> {service}
              </p>
            </div>

            <dl class="mt-auto grid grid-cols-3 gap-2 border-t border-base-300 pt-4 text-center">
              <div>
                <dt class="text-[11px] uppercase tracking-wide text-base-content/50">Leads</dt>
                <dd class="text-lg font-bold tabular-nums">{bucket.lead_count}</dd>
              </div>
              <div>
                <dt class="text-[11px] uppercase tracking-wide text-base-content/50">Strong</dt>
                <dd class="text-lg font-bold tabular-nums text-emerald-600">{bucket.strong_count}</dd>
              </div>
              <div>
                <dt class="text-[11px] uppercase tracking-wide text-base-content/50">Avg score</dt>
                <dd class="text-lg font-bold tabular-nums">
                  {if bucket.avg_score, do: round(bucket.avg_score), else: "—"}
                </dd>
              </div>
            </dl>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Leads.subscribe_buckets()
      Leads.subscribe_lookups()
    end

    {:ok,
     socket
     |> assign(:page_title, "Lead buckets")
     |> stream(:buckets, Leads.list_buckets())}
  end

  @impl true
  def handle_info({:lookup_updated, %{bucket_id: nil}}, socket), do: {:noreply, socket}

  def handle_info({event, _}, socket)
      when event in [:bucket_updated, :bucket_deleted, :lookup_updated] do
    # Counts and scores depend on many lookups, so refetch the (small) list.
    {:noreply, stream(socket, :buckets, Leads.list_buckets(), reset: true)}
  end
end
