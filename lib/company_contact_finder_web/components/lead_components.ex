defmodule CompanyContactFinderWeb.LeadComponents do
  @moduledoc """
  UI building blocks for leads and buckets, in GS1 Kenya colours: status
  badges, lead scores, fit badges, cards and buttons.
  """
  use Phoenix.Component

  import CompanyContactFinderWeb.CoreComponents, only: [icon: 1]

  @status_styles %{
    pending: {"Queued", "bg-base-300/60 text-base-content/70", "hero-clock"},
    searching:
      {"Searching", "bg-gs1-blue/10 text-gs1-blue dark:bg-white/10 dark:text-white",
       "hero-magnifying-glass"},
    crawling:
      {"Crawling", "bg-gs1-blue/10 text-gs1-blue dark:bg-white/10 dark:text-white",
       "hero-globe-alt"},
    analysing: {"Scoring", "bg-gs1-orange/10 text-gs1-orange-dark", "hero-sparkles"},
    done:
      {"Done", "bg-emerald-500/10 text-emerald-700 dark:text-emerald-400", "hero-check-circle"},
    failed:
      {"Failed", "bg-red-500/10 text-red-700 dark:text-red-400", "hero-exclamation-triangle"}
  }

  attr :status, :atom, required: true
  attr :id, :string, default: nil

  def status_badge(assigns) do
    {label, classes, icon} = Map.fetch!(@status_styles, assigns.status)
    busy? = assigns.status in [:searching, :crawling, :analysing]
    assigns = assign(assigns, label: label, classes: classes, icon: icon, busy?: busy?)

    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium",
        @classes
      ]}
    >
      <.icon name={@icon} class={["size-3.5", @busy? && "motion-safe:animate-pulse"]} />
      {@label}
    </span>
    """
  end

  attr :score, :integer, default: nil
  attr :size, :string, default: "sm", values: ~w(sm lg)

  def lead_score(%{score: nil} = assigns) do
    ~H"""
    <span class="text-sm text-base-content/40">—</span>
    """
  end

  def lead_score(assigns) do
    {text_tone, surface_tone} =
      cond do
        assigns.score >= 70 ->
          {"text-emerald-600 dark:text-emerald-400", "bg-emerald-500/10 ring-emerald-500/20"}

        assigns.score >= 40 ->
          {"text-amber-600 dark:text-amber-400", "bg-amber-500/10 ring-amber-500/20"}

        true ->
          {"text-red-600 dark:text-red-400", "bg-red-500/10 ring-red-500/20"}
      end

    assigns = assign(assigns, text_tone: text_tone, surface_tone: surface_tone)

    ~H"""
    <div
      :if={@size == "lg"}
      class="relative grid size-20 shrink-0 place-items-center"
      role="img"
      aria-label={"Lead score: #{@score} out of 100"}
    >
      <div class={[
        "absolute inset-1.5 rounded-full shadow-sm ring-1 ring-inset",
        @surface_tone
      ]}>
      </div>
      <svg
        viewBox="0 0 40 40"
        class={[
          "absolute inset-0 size-full -rotate-90 drop-shadow-sm",
          @text_tone
        ]}
        aria-hidden="true"
      >
        <circle
          cx="20"
          cy="20"
          r="17.5"
          fill="none"
          stroke="currentColor"
          stroke-opacity="0.12"
          stroke-width="2.5"
        />
        <circle
          cx="20"
          cy="20"
          r="17.5"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          pathLength="100"
          stroke-dasharray={"#{@score} 100"}
        />
      </svg>
      <span class="relative flex flex-col items-center font-bold leading-none tabular-nums">
        <span class={["text-2xl tracking-tight", @text_tone]}>{@score}</span>
        <span class="mt-1 text-[9px] font-semibold tracking-wide text-base-content/45">/ 100</span>
      </span>
    </div>

    <span
      :if={@size == "sm"}
      class={[
        "inline-flex min-w-9 items-center justify-center rounded-lg px-2 py-0.5 text-sm font-bold tabular-nums ring-1 ring-inset",
        @text_tone,
        @surface_tone
      ]}
      aria-label={"Lead score: #{@score} out of 100"}
    >
      {@score}
    </span>
    """
  end

  @fit_styles %{
    "strong" => {"Strong fit", "bg-emerald-500/10 text-emerald-700 dark:text-emerald-400"},
    "partial" => {"Partial fit", "bg-amber-500/10 text-amber-700 dark:text-amber-400"},
    "weak" => {"Weak fit", "bg-base-300/70 text-base-content/60"},
    "unknown" => {"Fit unknown", "bg-base-200 text-base-content/50"}
  }

  attr :fit, :string, default: nil
  attr :id, :string, default: nil

  def fit_badge(%{fit: nil} = assigns), do: ~H""

  def fit_badge(assigns) do
    {label, classes} = Map.get(@fit_styles, assigns.fit, @fit_styles["unknown"])
    assigns = assign(assigns, label: label, classes: classes)

    ~H"""
    <span
      id={@id}
      class={["inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold", @classes]}
    >
      {@label}
    </span>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section
      class={[
        "rounded-2xl border border-base-300 bg-base-100 shadow-sm shadow-gs1-blue/[0.04]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  A GS1-styled button. Renders a `<.link>` when `navigate`, `patch` or
  `href` is given, otherwise a `<button>`.
  """
  attr :variant, :string, default: "primary", values: ~w(primary secondary outline ghost)
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(href navigate patch method download type disabled name value form)

  slot :inner_block, required: true

  def brand_button(%{rest: rest} = assigns) do
    variant =
      %{
        "primary" =>
          "bg-gs1-orange text-white shadow-sm shadow-gs1-orange/25 hover:bg-gs1-orange-dark",
        "secondary" => "bg-gs1-blue text-white shadow-sm hover:bg-gs1-blue-light",
        "outline" =>
          "border border-base-300 bg-base-100 text-base-content hover:border-gs1-blue/40 hover:text-gs1-blue dark:hover:text-white",
        "ghost" => "text-gs1-blue hover:bg-gs1-blue/5 dark:text-white dark:hover:bg-white/10"
      }
      |> Map.fetch!(assigns.variant)

    size =
      %{
        "sm" => "px-2.5 py-1.5 text-xs",
        "md" => "px-4 py-2 text-sm",
        "lg" => "px-5 py-3 text-sm"
      }
      |> Map.fetch!(assigns.size)

    assigns =
      assign(assigns, :classes, [
        "inline-flex items-center justify-center gap-1.5 rounded-lg font-semibold transition active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50 phx-submit-loading:opacity-70 phx-click-loading:opacity-70",
        variant,
        size,
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@classes} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button class={@classes} {@rest}>{render_slot(@inner_block)}</button>
      """
    end
  end

  @doc "Tailwind classes for text inputs and textareas, in GS1 style."
  def field_class(size \\ :md) do
    [
      "w-full rounded-lg border border-base-300 bg-base-100 outline-none transition placeholder:text-base-content/40 focus:border-gs1-blue focus:ring-4 focus:ring-gs1-blue/10 dark:focus:border-gs1-orange dark:focus:ring-gs1-orange/15",
      if(size == :lg, do: "px-4 py-3 text-base", else: "px-3 py-2 text-sm")
    ]
  end

  @doc "Renders a link only for http(s) URLs; anything else is shown as text."
  attr :href, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def external_link(assigns) do
    assigns = assign(assigns, :safe?, safe_url?(assigns.href))

    ~H"""
    <a
      :if={@safe?}
      href={@href}
      target="_blank"
      rel="noopener noreferrer nofollow"
      class={@class}
    >
      {render_slot(@inner_block)}
    </a>
    <span :if={!@safe?} class={@class}>{render_slot(@inner_block)}</span>
    """
  end

  def safe_url?(url) when is_binary(url), do: String.match?(url, ~r/^https?:\/\//i)
  def safe_url?(_), do: false

  def display_host(nil), do: nil
  def display_host(url), do: URI.parse(url).host || url
end
