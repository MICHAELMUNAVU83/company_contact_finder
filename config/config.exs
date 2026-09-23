# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :company_contact_finder,
  ecto_repos: [CompanyContactFinder.Repo],
  generators: [timestamp_type: :utc_datetime]

# Lead pipeline: search, crawl and AI analysis.
# API keys are read from the environment in config/runtime.exs.
# Country the lead searches are scoped to (Google `gl` code and name).
config :company_contact_finder, :search,
  country_code: "ke",
  country_name: "Kenya"

config :company_contact_finder, :serper,
  base_url: "https://google.serper.dev",
  req_options: []

config :company_contact_finder, :openai,
  base_url: "https://api.openai.com/v1",
  model: "gpt-4.1-mini",
  req_options: []

config :company_contact_finder, :scraper,
  max_pages: 10,
  request_timeout: 10_000,
  max_body_bytes: 2_000_000,
  crawl_delay_ms: 500,
  max_redirects: 3,
  user_agent: "GS1KenyaLeadFinder/1.0 (+https://www.gs1kenya.org)",
  # Resolve hostnames and refuse private/loopback IPs (SSRF guard).
  resolve_dns_guard: true,
  req_options: []

config :company_contact_finder, :lookups, max_concurrency: 3

# Configure the endpoint
config :company_contact_finder, CompanyContactFinderWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CompanyContactFinderWeb.ErrorHTML, json: CompanyContactFinderWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CompanyContactFinder.PubSub,
  live_view: [signing_salt: "vteMoDKs"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :company_contact_finder, CompanyContactFinder.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  company_contact_finder: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  company_contact_finder: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
