defmodule CompanyContactFinder.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CompanyContactFinderWeb.Telemetry,
      CompanyContactFinder.Repo,
      {DNSCluster,
       query: Application.get_env(:company_contact_finder, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CompanyContactFinder.PubSub},
      {Task.Supervisor, name: CompanyContactFinder.TaskSupervisor},
      # Start to serve requests, typically the last entry
      CompanyContactFinderWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CompanyContactFinder.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CompanyContactFinderWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
