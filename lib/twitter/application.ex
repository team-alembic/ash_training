defmodule Twitter.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Ecto.DevLogger.install(Twitter.Repo)

    children = [
      TwitterWeb.Telemetry,
      Twitter.Repo,
      {DNSCluster, query: Application.get_env(:twitter, :dns_cluster_query) || :ignore},
      # Start the Finch HTTP client for sending emails
      {Phoenix.PubSub, name: Twitter.PubSub},
      {Finch, name: Twitter.Finch},
      TwitterWeb.Endpoint,
      {AshAuthentication.Supervisor, otp_app: :twitter}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Twitter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TwitterWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
