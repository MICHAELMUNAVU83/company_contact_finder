defmodule CompanyContactFinderWeb.ClientLive.Index do
  use CompanyContactFinderWeb, :live_view

  alias CompanyContactFinder.Clients
  alias CompanyContactFinder.Clients.Client
  alias CompanyContactFinder.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:clients}>
      <div class="space-y-8">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold tracking-tight text-gs1-blue dark:text-white sm:text-3xl">
              Clients
            </h1>
            <p class="mt-1 max-w-xl text-sm text-base-content/60">
              Companies that are already GS1 Kenya clients. Upsell buckets score this list.
              Fresh-acquire search skips these names.
            </p>
          </div>
          <p id="client-count" class="text-sm font-medium text-base-content/60">
            {@client_count} clients
          </p>
        </div>

        <.card class="space-y-4 p-6">
          <div>
            <h2 class="text-base font-bold text-gs1-blue dark:text-white">Upload a CSV</h2>
            <p class="mt-1 text-sm text-base-content/60">
              Header row: company, email, phone, website. A file of company names also works.
              Uploading the same company again updates its email, phone and website.
            </p>
          </div>
          <form id="client-upload" phx-change="validate" phx-submit="import" class="space-y-3">
            <.live_file_input upload={@uploads.clients} class={field_class()} />
            <p :for={err <- upload_errors(@uploads.clients)} class="text-sm text-error">
              {upload_error(err)}
            </p>
            <div :for={entry <- @uploads.clients.entries} class="text-sm text-base-content/70">
              <p>{entry.client_name}</p>
              <p :for={err <- upload_errors(@uploads.clients, entry)} class="text-error">
                {upload_error(err)}
              </p>
            </div>
            <div class="flex justify-end">
              <.brand_button type="submit" id="import-clients" phx-disable-with="Uploading...">
                <.icon name="hero-arrow-up-tray" class="size-4" /> Upload clients
              </.brand_button>
            </div>
          </form>
        </.card>

        <div
          :if={@client_count == 0}
          id="clients-empty"
          class="flex flex-col items-center gap-3 rounded-2xl border-2 border-dashed border-base-300 px-6 py-16 text-center"
        >
          <span class="grid size-12 place-items-center rounded-2xl bg-gs1-orange/10 text-gs1-orange">
            <.icon name="hero-building-office-2" class="size-6" />
          </span>
          <p class="font-semibold">No clients uploaded</p>
          <p class="max-w-sm text-sm text-base-content/50">
            Export your member or customer list as CSV and upload it here.
          </p>
        </div>

        <div
          :if={@clients != []}
          id="clients"
          class="overflow-hidden rounded-2xl border border-base-300 bg-base-100"
        >
          <p
            :if={@client_count > length(@clients)}
            class="border-b border-base-300 px-5 py-3 text-xs text-base-content/50"
          >
            Showing {length(@clients)} of {@client_count}. An upsell bucket can add the full list.
          </p>
          <ul class="divide-y divide-base-300">
            <li
              :for={client <- @clients}
              id={"client-#{client.id}"}
              class="flex items-start justify-between gap-3 px-5 py-4"
            >
              <div class="min-w-0">
                <p class="truncate font-semibold text-gs1-blue dark:text-white">
                  {client.company_name}
                </p>
                <p class="mt-0.5 truncate text-sm text-base-content/60">
                  {client_details(client)}
                </p>
              </div>
              <button
                id={"delete-client-#{client.id}"}
                type="button"
                phx-click="delete"
                phx-value-id={client.id}
                data-confirm={"Remove #{client.company_name} from the client list?"}
                class="inline-flex size-8 shrink-0 items-center justify-center rounded-lg text-base-content/60 transition hover:bg-red-500/10 hover:text-red-600"
                aria-label={"Remove #{client.company_name}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Clients")
     |> allow_upload(:clients,
       accept: ~w(.csv text/csv text/plain),
       max_entries: 1,
       max_file_size: 2_000_000
     )
     |> load_clients()}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("import", _params, socket) do
    texts =
      consume_uploaded_entries(socket, :clients, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case texts do
      [text] ->
        counts = Clients.import_csv(text)

        {:noreply,
         socket
         |> put_flash(:info, import_message(counts))
         |> load_clients()}

      _ ->
        {:noreply, put_flash(socket, :error, "Choose a CSV file first.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Repo.get(Client, id) do
      nil ->
        {:noreply, load_clients(socket)}

      client ->
        {:ok, _} = Clients.delete_client(client)

        {:noreply,
         socket
         |> put_flash(:info, "#{client.company_name} removed from the client list.")
         |> load_clients()}
    end
  end

  defp client_details(client) do
    [client.email, client.phone, client.website_url]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp load_clients(socket) do
    socket
    |> assign(:clients, Clients.list_clients())
    |> assign(:client_count, Clients.count_clients())
  end

  defp import_message(counts) do
    base = "Added #{counts.inserted}. Updated #{counts.updated}. Skipped #{counts.skipped}."

    if counts.truncated do
      base <> " Only the first 5,000 rows were read."
    else
      base
    end
  end

  defp upload_error(:too_large), do: "That file is larger than 2 MB."
  defp upload_error(:not_accepted), do: "Upload a .csv file."
  defp upload_error(:too_many_files), do: "Upload one file at a time."
  defp upload_error(other), do: "Upload failed: #{inspect(other)}"
end
