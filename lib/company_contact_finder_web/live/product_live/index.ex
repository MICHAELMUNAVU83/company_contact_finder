defmodule CompanyContactFinderWeb.ProductLive.Index do
  use CompanyContactFinderWeb, :live_view

  alias CompanyContactFinder.Catalog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:products}>
      <div class="space-y-8">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold tracking-tight text-gs1-blue dark:text-white sm:text-3xl">
              Products
            </h1>
            <p class="mt-1 max-w-xl text-sm text-base-content/60">
              Offerings the lead finder can pitch. Each one says who it is for,
              who it is not for, and the two facts an email can cite.
            </p>
          </div>
          <.brand_button navigate={~p"/products/new"} id="new-product">
            <.icon name="hero-plus" class="size-4" /> New product
          </.brand_button>
        </div>

        <div id="products" phx-update="stream" class="grid gap-4 sm:grid-cols-2">
          <div
            id="products-empty"
            class="hidden flex-col items-center gap-3 rounded-2xl border-2 border-dashed border-base-300 px-6 py-16 text-center only:flex sm:col-span-2"
          >
            <span class="grid size-12 place-items-center rounded-2xl bg-gs1-orange/10 text-gs1-orange">
              <.icon name="hero-tag" class="size-6" />
            </span>
            <p class="font-semibold">No products yet</p>
            <p class="max-w-sm text-sm text-base-content/50">
              Add a product before you attach it to a lead bucket.
            </p>
            <div class="flex flex-wrap items-center justify-center gap-2">
              <.brand_button navigate={~p"/products/new"} variant="secondary" size="sm">
                Create a product
              </.brand_button>
              <button
                id="load-starter-products"
                type="button"
                phx-click="load_starter"
                class="text-sm font-medium text-gs1-blue underline-offset-2 hover:underline dark:text-white"
              >
                Load the starter catalog
              </button>
            </div>
          </div>

          <.card
            :for={{dom_id, product} <- @streams.products}
            id={dom_id}
            class="flex flex-col gap-4 p-5"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h2 class="truncate text-base font-bold text-gs1-blue dark:text-white">
                  {product.name}
                </h2>
                <p class="mt-1 line-clamp-2 text-sm text-base-content/70">{product.audience}</p>
              </div>
              <div class="flex shrink-0 items-center gap-1">
                <.link
                  id={"edit-product-#{product.id}"}
                  navigate={~p"/products/#{product}/edit"}
                  class="inline-flex size-8 items-center justify-center rounded-lg text-base-content/60 transition hover:bg-base-200 hover:text-gs1-blue dark:hover:text-white"
                  aria-label={"Edit #{product.name}"}
                >
                  <.icon name="hero-pencil-square" class="size-4" />
                </.link>
                <button
                  id={"delete-product-#{product.id}"}
                  type="button"
                  phx-click="delete"
                  phx-value-id={product.id}
                  data-confirm={"Delete #{product.name}? Buckets that offer it will drop it."}
                  class="inline-flex size-8 items-center justify-center rounded-lg text-base-content/60 transition hover:bg-red-500/10 hover:text-red-600"
                  aria-label={"Delete #{product.name}"}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>

            <p class="text-sm text-base-content/60">
              <span class="font-medium text-base-content/80">Not for</span>
              {product.not_for}
            </p>

            <ul class="space-y-1.5 text-sm text-base-content/70">
              <li :for={point <- product.proof_points} class="flex gap-2">
                <.icon name="hero-check" class="mt-0.5 size-4 shrink-0 text-gs1-orange" />
                <span>{point}</span>
              </li>
            </ul>

            <p class="mt-auto border-t border-base-300 pt-3 text-xs text-base-content/50">
              {product.owner_email}
            </p>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Products")
     |> stream(:products, Catalog.list_products())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = Catalog.get_product!(id)

    case Catalog.delete_product(product) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{product.name} deleted.")
         |> stream_delete(:products, product)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete that product.")}
    end
  end

  def handle_event("load_starter", _params, socket) do
    :ok = Catalog.seed_products()

    {:noreply, stream(socket, :products, Catalog.list_products(), reset: true)}
  end
end
