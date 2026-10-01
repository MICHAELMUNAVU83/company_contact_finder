defmodule CompanyContactFinderWeb.ProductLive.Form do
  use CompanyContactFinderWeb, :live_view

  alias CompanyContactFinder.Catalog
  alias CompanyContactFinder.Catalog.Product

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:products}>
      <div class="mx-auto max-w-3xl space-y-6">
        <.link
          navigate={~p"/products"}
          class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-gs1-blue dark:hover:text-white"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.link>

        <div>
          <h1 class="text-2xl font-bold tracking-tight text-gs1-blue dark:text-white sm:text-3xl">
            {@page_title}
          </h1>
          <p class="mt-1 text-sm text-base-content/60">
            The brief and the email drafter read this card when they recommend the product.
          </p>
        </div>

        <.form
          for={@form}
          id="product-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
        >
          <.card class="space-y-5 p-6">
            <.section_title number="1" title="What is it?" />
            <.input
              field={@form[:name]}
              type="text"
              label="Product name"
              placeholder="e.g. GS1 barcodes"
              class={field_class()}
            />
            <.input
              field={@form[:audience]}
              type="textarea"
              rows="2"
              label="Who it is for"
              placeholder="e.g. Manufacturers and exporters that are not GS1 members"
              class={field_class()}
            />
            <.input
              field={@form[:not_for]}
              type="textarea"
              rows="2"
              label="Who it is not for"
              placeholder="e.g. Companies that already have a GS1 company prefix"
              class={field_class()}
            />
          </.card>

          <.card class="space-y-5 p-6">
            <.section_title number="2" title="What can an email cite?" />
            <fieldset id="proof-points">
              <legend class="mb-2 text-sm font-medium">Two proof points</legend>
              <div class="space-y-3">
                <.proof_input index={0} value={proof_point(@form, 0)} />
                <.proof_input index={1} value={proof_point(@form, 1)} />
              </div>
              <p
                :for={{message, _} <- @form[:proof_points].errors}
                id="proof-points-error"
                class="mt-1.5 flex items-center gap-2 text-sm text-error"
              >
                <.icon name="hero-exclamation-circle" class="size-5" />
                {message}
              </p>
            </fieldset>
            <.input
              field={@form[:owner_email]}
              type="email"
              label="Owner email"
              placeholder="owner@example.com"
              class={field_class()}
            />
            <p class="-mt-2 text-xs text-base-content/50">
              Copied onto the brief and added as Cc when an email is drafted.
            </p>
          </.card>

          <div class="flex items-center justify-end gap-2">
            <.brand_button variant="outline" navigate={~p"/products"}>
              Cancel
            </.brand_button>
            <.brand_button type="submit" id="save-product" phx-disable-with="Saving...">
              {if @product.id, do: "Save changes", else: "Create product"}
            </.brand_button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  attr :number, :string, required: true
  attr :title, :string, required: true

  defp section_title(assigns) do
    ~H"""
    <h2 class="flex items-center gap-2.5 text-base font-bold text-gs1-blue dark:text-white">
      <span class="grid size-6 place-items-center rounded-full bg-gs1-orange text-xs font-bold text-white">
        {@number}
      </span>
      {@title}
    </h2>
    """
  end

  attr :index, :integer, required: true
  attr :value, :string, required: true

  defp proof_input(assigns) do
    ~H"""
    <label for={"product_proof_points_#{@index}"} class="block">
      <span class="mb-1 block text-sm font-medium">Proof point {@index + 1}</span>
      <input
        type="text"
        id={"product_proof_points_#{@index}"}
        name="product[proof_points][]"
        value={@value}
        placeholder="A concrete thing this product does"
        class={field_class()}
      />
    </label>
    """
  end

  defp proof_point(form, index) do
    case form[:proof_points].value do
      points when is_list(points) -> Enum.at(points, index) || ""
      _ -> ""
    end
  end

  @impl true
  def mount(params, _session, socket) do
    product =
      case socket.assigns.live_action do
        :edit -> Catalog.get_product!(params["id"])
        :new -> %Product{}
      end

    {:ok,
     socket
     |> assign(:product, product)
     |> assign(:page_title, if(product.id, do: "Edit #{product.name}", else: "New product"))
     |> assign(:form, to_form(Catalog.change_product(product)))}
  end

  @impl true
  def handle_event("validate", %{"product" => params}, socket) do
    changeset = Catalog.change_product(socket.assigns.product, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"product" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    case Catalog.create_product(params) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product created.")
         |> push_navigate(to: ~p"/products")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, :edit, params) do
    case Catalog.update_product(socket.assigns.product, params) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product updated.")
         |> push_navigate(to: ~p"/products")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
