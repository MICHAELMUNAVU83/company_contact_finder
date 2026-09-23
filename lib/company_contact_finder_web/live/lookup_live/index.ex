defmodule CompanyContactFinderWeb.LookupLive.Index do
  use CompanyContactFinderWeb, :live_view

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Lookup

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:leads}>
      <div class="space-y-10">
        <section class="relative overflow-hidden rounded-3xl bg-gs1-blue px-6 py-10 text-white shadow-lg shadow-gs1-blue/20 sm:px-10">
          <div class="pointer-events-none absolute -right-16 -top-16 size-64 rounded-full bg-gs1-orange/20 blur-2xl" />
          <div class="pointer-events-none absolute -bottom-24 left-1/3 size-72 rounded-full bg-white/5 blur-2xl" />

          <div class="relative mx-auto max-w-2xl text-center">
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-gs1-orange">
              GS1 Kenya · Lead Finder
            </p>
            <h1 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              Find companies that need GS1 standards
            </h1>
            <p class="mt-3 text-white/75">
              Type a company name. We find its website, collect its public contact details
              and score it against your lead bucket.
            </p>
          </div>

          <div class="relative mx-auto mt-8 max-w-2xl rounded-2xl bg-white p-2 text-base-content shadow-xl dark:bg-base-100">
            <div class="flex gap-1 rounded-xl bg-base-200 p-1" role="tablist">
              <button
                :for={{mode, label} <- [single: "One company", bulk: "Bulk list"]}
                id={"mode-#{mode}"}
                type="button"
                role="tab"
                aria-selected={to_string(@mode == mode)}
                phx-click="set_mode"
                phx-value-mode={mode}
                class={[
                  "flex-1 rounded-lg px-3 py-1.5 text-sm font-semibold transition",
                  if(@mode == mode,
                    do: "bg-base-100 text-gs1-blue shadow-sm dark:text-white",
                    else: "text-base-content/60 hover:text-gs1-blue dark:hover:text-white"
                  )
                ]}
              >
                {label}
              </button>
            </div>

            <.form
              :if={@mode == :single}
              for={@form}
              id="lookup-form"
              phx-change="validate"
              phx-submit="search"
              class="space-y-2 p-3"
            >
              <div class="flex flex-col gap-2 sm:flex-row sm:items-start">
                <div class="flex-1">
                  <.input
                    field={@form[:company_name]}
                    type="text"
                    placeholder="e.g. Acme Foods Nairobi"
                    autocomplete="off"
                    phx-debounce="300"
                    class={field_class(:lg)}
                  />
                </div>
                <.brand_button type="submit" size="lg" id="search-button">
                  <.icon name="hero-magnifying-glass" class="size-4" /> Find contacts
                </.brand_button>
              </div>
              <.bucket_picker field={@form[:bucket_id]} options={@bucket_options} />
            </.form>

            <.form
              :if={@mode == :bulk}
              for={@bulk_form}
              id="bulk-form"
              phx-submit="bulk"
              class="space-y-3 p-3"
            >
              <textarea
                id="bulk-names"
                name="bulk[names]"
                rows="6"
                placeholder="One company per line&#10;Acme Foods&#10;Globex Kenya&#10;Initech Ltd"
                class={field_class()}
              >{@bulk_form[:names].value}</textarea>
              <.bucket_picker field={@bulk_form[:bucket_id]} options={@bucket_options} />
              <div class="flex items-center justify-between gap-3">
                <p class="text-xs text-base-content/50">Up to 200 companies. A few run at a time.</p>
                <.brand_button type="submit" variant="secondary" id="bulk-button">
                  <.icon name="hero-queue-list" class="size-4" /> Queue lookups
                </.brand_button>
              </div>
            </.form>
          </div>
        </section>

        <section class="space-y-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-lg font-bold tracking-tight text-gs1-blue dark:text-white">
              Recent lookups
            </h2>
            <div class="flex items-center gap-1 rounded-lg bg-base-100 p-1 text-sm shadow-sm ring-1 ring-base-300">
              <.link
                :for={{sort, label} <- [recent: "Newest", score: "Best leads"]}
                id={"sort-#{sort}"}
                patch={~p"/?#{[sort: sort]}"}
                class={[
                  "rounded-md px-3 py-1 font-medium transition",
                  if(@sort == sort,
                    do: "bg-gs1-blue text-white",
                    else: "text-base-content/60 hover:text-gs1-blue dark:hover:text-white"
                  )
                ]}
              >
                {label}
              </.link>
            </div>
          </div>

          <.card class="overflow-hidden">
            <div class="hidden grid-cols-[minmax(0,2fr)_minmax(0,1.3fr)_minmax(0,1.3fr)_7rem_5rem] gap-4 border-b border-base-300 bg-base-200/60 px-5 py-2.5 text-xs font-semibold uppercase tracking-wide text-base-content/50 md:grid">
              <span>Company</span>
              <span>Bucket</span>
              <span>Website</span>
              <span>Status</span>
              <span class="text-right">Score</span>
            </div>

            <ul id="lookups" phx-update="stream" class="divide-y divide-base-300">
              <li
                id="lookups-empty"
                class="hidden flex-col items-center gap-2 px-6 py-16 text-center only:flex"
              >
                <span class="grid size-12 place-items-center rounded-2xl bg-gs1-blue/10 text-gs1-blue dark:text-white">
                  <.icon name="hero-building-office-2" class="size-6" />
                </span>
                <p class="font-semibold">No lookups yet</p>
                <p class="text-sm text-base-content/50">Search for a company above to get started.</p>
              </li>

              <li :for={{dom_id, lookup} <- @streams.lookups} id={dom_id}>
                <.link
                  navigate={~p"/lookups/#{lookup}"}
                  class="group grid grid-cols-[1fr_auto] items-center gap-x-4 gap-y-1 px-5 py-4 transition hover:bg-gs1-blue/3 md:grid-cols-[minmax(0,2fr)_minmax(0,1.3fr)_minmax(0,1.3fr)_7rem_5rem]"
                >
                  <div class="min-w-0">
                    <p class="truncate font-semibold group-hover:text-gs1-blue dark:group-hover:text-gs1-orange">
                      {lookup.company_name}
                    </p>
                    <p class="truncate text-xs text-base-content/50">
                      {(lookup.brief && lookup.brief.industry) ||
                        Calendar.strftime(lookup.inserted_at, "%b %-d, %H:%M")} · {lookup.contact_count ||
                        0} contacts
                    </p>
                  </div>
                  <p class="hidden truncate text-sm md:block">
                    <span :if={lookup.bucket} class="font-medium text-gs1-blue dark:text-white/80">
                      {lookup.bucket.name}
                    </span>
                    <span :if={!lookup.bucket} class="text-base-content/40">—</span>
                  </p>
                  <p class="hidden truncate text-sm text-base-content/60 md:block">
                    {display_host(lookup.website_url) || "—"}
                  </p>
                  <div class="justify-self-end md:justify-self-start">
                    <.status_badge status={lookup.status} />
                  </div>
                  <div class="hidden text-right md:block">
                    <.lead_score score={lookup.brief && lookup.brief.lead_score} />
                  </div>
                </.link>
              </li>
            </ul>
          </.card>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :options, :list, required: true

  defp bucket_picker(%{options: []} = assigns) do
    ~H"""
    <p class="flex items-center gap-1.5 px-1 text-xs text-base-content/60">
      <.icon name="hero-light-bulb" class="size-4 text-gs1-orange" />
      <span>
        <.link
          navigate={~p"/buckets/new"}
          class="font-semibold text-gs1-blue hover:underline dark:text-white"
        >
          Create a lead bucket
        </.link>
        to score leads against the companies you want and the service you're offering.
      </span>
    </p>
    """
  end

  defp bucket_picker(assigns) do
    ~H"""
    <label class="flex flex-col gap-1.5 px-1 text-xs font-medium text-base-content/60 sm:flex-row sm:items-center">
      <span class="shrink-0">Score against bucket</span>
      <select id={@field.id} name={@field.name} class={[field_class(), "sm:max-w-xs"]}>
        <option value="">No bucket (general score)</option>
        {Phoenix.HTML.Form.options_for_select(@options, @field.value)}
      </select>
    </label>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Leads.subscribe_lookups()
      Leads.subscribe_buckets()
    end

    {:ok,
     socket
     |> assign(:page_title, "Find leads")
     |> assign(:mode, :single)
     |> assign(:bucket_options, Leads.bucket_options())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sort = if params["sort"] == "score", do: :score, else: :recent
    bucket_id = params["bucket"]

    {:noreply,
     socket
     |> assign(:sort, sort)
     |> assign(:form, to_form(Leads.change_lookup(%Lookup{}, %{"bucket_id" => bucket_id})))
     |> assign(:bulk_form, to_form(%{"names" => "", "bucket_id" => bucket_id}, as: :bulk))
     |> stream(:lookups, Leads.list_lookups(sort: sort), reset: true)}
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    mode = if mode == "bulk", do: :bulk, else: :single
    {:noreply, assign(socket, :mode, mode)}
  end

  def handle_event("validate", %{"lookup" => params}, socket) do
    changeset = Leads.change_lookup(%Lookup{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("search", %{"lookup" => params}, socket) do
    case Leads.start_lookup(params) do
      {:ok, lookup} ->
        {:noreply, push_navigate(socket, to: ~p"/lookups/#{lookup}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("bulk", %{"bulk" => %{"names" => names} = params}, socket) do
    bucket_id = blank_to_nil(params["bucket_id"])

    case Leads.start_bulk_lookups(names, bucket_id) do
      {:ok, []} ->
        {:noreply, put_flash(socket, :error, "Add at least one company name (2+ characters).")}

      {:ok, lookups} ->
        {:noreply,
         socket
         |> put_flash(:info, "Queued #{length(lookups)} lookups.")
         |> assign(:bulk_form, to_form(%{"names" => "", "bucket_id" => bucket_id}, as: :bulk))}
    end
  end

  @impl true
  def handle_info({:lookup_updated, %{id: id}}, socket) do
    case Leads.get_lookup_summary(id) do
      nil -> {:noreply, socket}
      lookup -> {:noreply, stream_insert(socket, :lookups, lookup, at: 0)}
    end
  end

  def handle_info({event, _bucket}, socket) when event in [:bucket_updated, :bucket_deleted] do
    {:noreply, assign(socket, :bucket_options, Leads.bucket_options())}
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
