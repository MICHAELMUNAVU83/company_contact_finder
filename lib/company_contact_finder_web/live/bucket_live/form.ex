defmodule CompanyContactFinderWeb.BucketLive.Form do
  use CompanyContactFinderWeb, :live_view

  alias CompanyContactFinder.Catalog
  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Bucket

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:buckets}>
      <div class="mx-auto max-w-3xl space-y-6">
        <.link
          navigate={if @bucket.id, do: ~p"/buckets/#{@bucket}", else: ~p"/buckets"}
          class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-gs1-blue dark:hover:text-white"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.link>

        <div>
          <h1 class="text-2xl font-bold tracking-tight text-gs1-blue dark:text-white sm:text-3xl">
            {@page_title}
          </h1>
          <p class="mt-1 text-sm text-base-content/60">
            Describe the companies you want and the GS1 Kenya service you'll offer them.
            Every lead in this bucket is scored against it.
          </p>
        </div>

        <.form for={@form} id="bucket-form" phx-change="validate" phx-submit="save" class="space-y-6">
          <.card class="space-y-5 p-6">
            <.section_title number="1" title="Name the bucket" />
            <.input
              field={@form[:name]}
              type="text"
              label="Bucket name"
              placeholder="e.g. Nairobi food manufacturers"
              class={field_class()}
            />
          </.card>

          <.card class="space-y-5 p-6">
            <.section_title number="2" title="Which leads do you want?" />
            <.input
              field={@form[:target_description]}
              type="textarea"
              rows="3"
              label="Target leads"
              placeholder="e.g. Kenyan food and beverage manufacturers that sell packaged products through supermarkets or want to export."
              class={field_class()}
            />
            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@form[:industries]}
                value={join(@form[:industries].value)}
                type="text"
                label="Industries (comma separated)"
                placeholder="Food processing, Beverages, Cosmetics"
                class={field_class()}
              />
              <.input
                field={@form[:locations]}
                value={join(@form[:locations].value)}
                type="text"
                label="Locations (comma separated)"
                placeholder="Nairobi, Mombasa, Kenya"
                class={field_class()}
              />
            </div>

            <fieldset id="company-sizes">
              <legend class="mb-2 text-sm font-medium">Company sizes</legend>
              <input type="hidden" name="bucket[company_sizes][]" value="" />
              <div class="flex flex-wrap gap-2">
                <label
                  :for={size <- Bucket.sizes()}
                  class={[
                    "cursor-pointer rounded-lg border px-3 py-1.5 text-sm font-medium capitalize transition",
                    if(size in (@form[:company_sizes].value || []),
                      do: "border-gs1-blue bg-gs1-blue text-white",
                      else: "border-base-300 hover:border-gs1-blue/40"
                    )
                  ]}
                >
                  <input
                    type="checkbox"
                    name="bucket[company_sizes][]"
                    value={size}
                    checked={size in (@form[:company_sizes].value || [])}
                    class="sr-only"
                  />
                  {size}
                </label>
              </div>
              <p class="mt-1.5 text-xs text-base-content/50">Leave empty for any size.</p>
            </fieldset>

            <.input
              field={@form[:disqualifiers]}
              type="textarea"
              rows="2"
              label="Not a fit (optional)"
              placeholder="e.g. Already GS1 members, pure retailers, service-only businesses"
              class={field_class()}
            />
          </.card>

          <.card class="space-y-5 p-6">
            <.section_title number="3" title="What will you offer them?" />
            <fieldset id="products">
              <legend class="mb-2 text-sm font-medium">Products</legend>
              <input type="hidden" name="bucket[product_ids][]" value="" />
              <div class="flex flex-wrap gap-2">
                <label
                  :for={product <- @products}
                  class="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-base-300 px-3 py-1.5 text-sm"
                >
                  <input
                    type="checkbox"
                    name="bucket[product_ids][]"
                    value={product.id}
                    checked={product.id in selected_product_ids(@form)}
                  />
                  {product.name}
                </label>
              </div>
              <p :for={{message, _} <- @form[:product_ids].errors} class="mt-1 text-sm text-red-600">
                {message}
              </p>
              <p class="mt-2 text-xs text-base-content/50">
                <.link
                  navigate={~p"/products"}
                  class="font-medium text-gs1-blue hover:underline dark:text-white"
                >
                  Manage products
                </.link>
              </p>
            </fieldset>
            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@form[:breadth]}
                type="select"
                label="Search breadth"
                options={[{"Narrow", "narrow"}, {"Wide", "wide"}]}
              />
              <.input
                field={@form[:max_companies]}
                type="number"
                label="Max companies"
                min="1"
                max="500"
              />
            </div>
            <p class="text-xs text-base-content/50">
              Set breadth to Wide and this to 200 or more for a full run.
              Each company you add is still crawled and scored on its own.
            </p>
            <.input
              field={@form[:service_details]}
              type="textarea"
              rows="3"
              label="Offer details (optional)"
              placeholder="e.g. Company prefix and first 100 GTINs, onboarding training, help getting listed with major supermarkets."
              class={field_class()}
            />
          </.card>

          <div class="flex items-center justify-end gap-2">
            <.brand_button
              variant="outline"
              navigate={if @bucket.id, do: ~p"/buckets/#{@bucket}", else: ~p"/buckets"}
            >
              Cancel
            </.brand_button>
            <.brand_button type="submit" id="save-bucket" phx-disable-with="Saving...">
              {if @bucket.id, do: "Save changes", else: "Create bucket"}
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

  defp products do
    Catalog.seed_products()
    Catalog.list_products()
  end

  defp join(list) when is_list(list), do: Enum.join(list, ", ")
  defp join(value), do: value

  defp selected_product_ids(form) do
    case form[:product_ids].value do
      list when is_list(list) ->
        Enum.flat_map(list, fn
          id when is_integer(id) ->
            [id]

          id when is_binary(id) ->
            case Integer.parse(id) do
              {int, ""} -> [int]
              _ -> []
            end

          _ ->
            []
        end)

      _ ->
        []
    end
  end

  @impl true
  def mount(params, _session, socket) do
    bucket =
      case socket.assigns.live_action do
        :edit -> Leads.get_bucket!(params["id"])
        :new -> %Bucket{}
      end

    {:ok,
     socket
     |> assign(:bucket, bucket)
     |> assign(:products, products())
     |> assign(:page_title, if(bucket.id, do: "Edit #{bucket.name}", else: "New lead bucket"))
     |> assign(:form, to_form(Leads.change_bucket(bucket)))}
  end

  @impl true
  def handle_event("validate", %{"bucket" => params}, socket) do
    changeset = Leads.change_bucket(socket.assigns.bucket, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"bucket" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    case Leads.create_bucket(params) do
      {:ok, bucket} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bucket created. Add companies to start scoring leads.")
         |> push_navigate(to: ~p"/buckets/#{bucket}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp save(socket, :edit, params) do
    case Leads.update_bucket(socket.assigns.bucket, params) do
      {:ok, bucket} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bucket saved. Rescore its leads to apply the new criteria.")
         |> push_navigate(to: ~p"/buckets/#{bucket}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end
end
