defmodule Bolognesa.Application do
  alias Bolognesa.Infrastructure.Jobs.IdentificationReconciler
  alias BolognesaWeb.Endpoint
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TwMerge.Cache,
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
        optional_children(:scan_reconciler, [
          {Bolognesa.Libraries.Infrastructure.Jobs.Reconcilers.LibraryJobReconciler,
           operation: :scan}
        ]) ++
        optional_children(:inspection_reconciler, [
          {Bolognesa.Libraries.Infrastructure.Jobs.Reconcilers.LibraryJobReconciler,
           operation: :inspection}
        ]) ++
        optional_children(:identification_reconciler, [
          {IdentificationReconciler,
           context: :movies,
           name: Bolognesa.Movies.Infrastructure.Jobs.Reconcilers.IdentificationReconciler,
           use_case: Bolognesa.Movies.Application.UseCases.ReconcileIdentifications,
           repository: Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository},
          {IdentificationReconciler,
           context: :series,
           name: Bolognesa.Series.Infrastructure.Jobs.Reconcilers.IdentificationReconciler,
           use_case: Bolognesa.Series.Application.UseCases.ReconcileIdentifications,
           repository: Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository}
        ]) ++
        optional_children(:music_import_reconciler, [
          Bolognesa.Music.Infrastructure.Jobs.Reconcilers.ImportReconciler
        ])

    opts = [strategy: :one_for_one, name: Bolognesa.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp optional_children(key, children),
    do: if(Application.get_env(:bolognesa, key, true), do: children, else: [])

  @impl true
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
