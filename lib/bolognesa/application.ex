defmodule Bolognesa.Application do
  alias BolognesaWeb.Endpoint
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
      Bolognesa.Playback.Infrastructure.TranscodeManager,
      Endpoint
    ]

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
      do: [
        {Bolognesa.Libraries.Infrastructure.Jobs.Reconcilers.LibraryJobReconciler,
         operation: :scan}
      ],
      else: []
  end

  defp inspection_reconciler_children do
    if Application.get_env(:bolognesa, :inspection_reconciler, true),
      do: [
        {Bolognesa.Libraries.Infrastructure.Jobs.Reconcilers.LibraryJobReconciler,
         operation: :inspection}
      ],
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

  @impl true
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
