defmodule CompanyContactFinderWeb.BucketLive.Form do
  use CompanyContactFinderWeb, :live_view

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
            <div>
              <.input
                field={@form[:service]}
                type="text"
                label="Service"
                list="service-options"
                placeholder="Pick or type a service"
                class={field_class()}
              />
              <datalist id="service-options">
                <option :for={service <- Bucket.services()} value={service} />
              </datalist>
              <div class="mt-2 flex flex-wrap gap-1.5">
                <button
                  :for={service <- Bucket.services()}
                  type="button"
                  phx-click="pick_service"
                  phx-value-service={service}
                  class={[
                    "rounded-full border px-2.5 py-1 text-xs font-medium transition",
                    if(@form[:service].value == service,
                      do: "border-gs1-orange bg-gs1-orange text-white",
                      else:
                        "border-base-300 text-base-content/70 hover:border-gs1-orange hover:text-gs1-orange"
                    )
                  ]}
                >
                  {service}
                </button>
              </div>
            </div>
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

  defp join(list) when is_list(list), do: Enum.join(list, ", ")
  defp join(value), do: value

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
     |> assign(:page_title, if(bucket.id, do: "Edit #{bucket.name}", else: "New lead bucket"))
     |> assign(:form, to_form(Leads.change_bucket(bucket)))}
  end

  @impl true
  def handle_event("validate", %{"bucket" => params}, socket) do
    changeset = Leads.change_bucket(socket.assigns.bucket, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("pick_service", %{"service" => service}, socket) do
    params = Map.put(socket.assigns.form.params, "service", service)
    changeset = Leads.change_bucket(socket.assigns.bucket, params)
    {:noreply, assign(socket, :form, to_form(changeset))}
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
