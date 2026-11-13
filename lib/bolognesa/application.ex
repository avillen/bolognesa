defmodule Bolognesa.Application do
  alias BolognesaWeb.Endpoint
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Bolognesa.Infrastructure.Observability,
      BolognesaWeb.Telemetry,
      Bolognesa.Infrastructure.Observability.PromEx,
      Bolognesa.Repo,
      {Phoenix.PubSub, name: Bolognesa.PubSub},
      {Oban, Application.fetch_env!(:bolognesa, Oban)},
      {DNSCluster, query: Application.get_env(:bolognesa, :dns_cluster_query) || :ignore},
      Bolognesa.Playback.Infrastructure.TranscodeManager,
      # Start a worker by calling: Bolognesa.Worker.start_link(arg)
      # {Bolognesa.Worker, arg},
      # Start to serve requests, typically the last entry
      Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    children =
      children ++
        scan_reconciler_children() ++
        inspection_reconciler_children() ++
        identification_reconciler_children() ++ music_children()

    opts = [strategy: :one_for_one, name: Bolognesa.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp scan_reconciler_children do
    if Application.get_env(:bolognesa, :scan_reconciler, true),
      do: [Bolognesa.Libraries.Infrastructure.Jobs.Reconcilers.ScanReconciler],
      else: []
  end

  defp inspection_reconciler_children do
    if Application.get_env(:bolognesa, :inspection_reconciler, true),
      do: [Bolognesa.Libraries.Infrastructure.Jobs.Reconcilers.InspectionReconciler],
      else: []
  end

  defp identification_reconciler_children do
    if Application.get_env(:bolognesa, :identification_reconciler, true),
      do: [
        Bolognesa.Movies.Infrastructure.Jobs.Reconcilers.IdentificationReconciler,
        Bolognesa.Series.Infrastructure.Jobs.Reconcilers.IdentificationReconciler
      ],
      else: []
  end

  defp music_children do
    if Application.get_env(:bolognesa, :music_import_reconciler, true),
      do: [Bolognesa.Music.Infrastructure.Jobs.Reconcilers.ImportReconciler],
      else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
