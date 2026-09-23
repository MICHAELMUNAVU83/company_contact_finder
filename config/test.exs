import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :company_contact_finder, CompanyContactFinder.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "company_contact_finder_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :company_contact_finder, CompanyContactFinderWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "RgYMxaTm0mLV2e/osdlP6sLIxlJzFzNVyEM1/fLS9ssaS3rj15CmOmcIzHeIb7Eb",
  server: false

# Stub all outbound HTTP in tests with Req.Test.
config :company_contact_finder, :serper,
  api_key: "test-serper-key",
  req_options: [plug: {Req.Test, CompanyContactFinder.Search.Serper}, retry: false]

config :company_contact_finder, :openai,
  api_key: "test-openai-key",
  model: "test-model",
  req_options: [plug: {Req.Test, CompanyContactFinder.AI.OpenAI}, retry: false]

config :company_contact_finder, :scraper,
  crawl_delay_ms: 0,
  resolve_dns_guard: false,
  req_options: [plug: {Req.Test, CompanyContactFinder.Scraper.Crawler}, retry: false]

# In test we don't send emails
config :company_contact_finder, CompanyContactFinder.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
