defmodule CompanyContactFinder.Repo do
  use Ecto.Repo,
    otp_app: :company_contact_finder,
    adapter: Ecto.Adapters.Postgres
end
