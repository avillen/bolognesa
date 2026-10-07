defmodule Bolognesa.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BolognesaWeb.Telemetry,
      Bolognesa.Repo,
      {Oban, Application.fetch_env!(:bolognesa, Oban)},
      {DNSCluster, query: Application.get_env(:bolognesa, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Bolognesa.PubSub},
      # Start a worker by calling: Bolognesa.Worker.start_link(arg)
      # {Bolognesa.Worker, arg},
      # Start to serve requests, typically the last entry
      BolognesaWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    children =
      children ++
        scan_reconciler_children() ++
        outbox_dispatcher_children() ++
        inspection_reconciler_children() ++
        identification_outbox_children() ++
        identification_reconciler_children()

    opts = [strategy: :one_for_one, name: Bolognesa.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp scan_reconciler_children do
    if Application.get_env(:bolognesa, :scan_reconciler, true),
      do: [Bolognesa.Libraries.Infrastructure.Jobs.ScanReconciler],
      else: []
  end

  defp outbox_dispatcher_children do
    if Application.get_env(:bolognesa, :inspection_outbox_dispatcher, true),
      do: [Bolognesa.Libraries.Infrastructure.Jobs.OutboxDispatcher],
      else: []
  end

  defp inspection_reconciler_children do
    if Application.get_env(:bolognesa, :inspection_reconciler, true),
      do: [Bolognesa.Libraries.Infrastructure.Jobs.InspectionReconciler],
      else: []
  end

  defp identification_outbox_children do
    if Application.get_env(:bolognesa, :identification_outbox_dispatcher, true),
      do: [Bolognesa.Identification.Infrastructure.Jobs.OutboxDispatcher],
      else: []
  end

  defp identification_reconciler_children do
    if Application.get_env(:bolognesa, :identification_reconciler, true),
      do: [Bolognesa.Identification.Infrastructure.Jobs.IdentificationReconciler],
      else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BolognesaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
