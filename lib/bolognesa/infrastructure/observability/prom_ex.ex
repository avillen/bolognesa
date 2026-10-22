defmodule Bolognesa.Infrastructure.Observability.PromEx do
  @moduledoc "Optional Prometheus exporter; collection and network access are disabled by default."

  use PromEx, otp_app: :bolognesa

  alias Bolognesa.Infrastructure.Observability.EctoMetrics
  alias Bolognesa.Infrastructure.Observability.LiveViewMetrics
  alias Bolognesa.Infrastructure.Observability.OperationalMetrics
  alias Bolognesa.Infrastructure.Observability.PhoenixMetrics
  alias Bolognesa.Infrastructure.Observability.PlaybackMetrics
  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      {Plugins.Beam, poll_rate: 60_000},
      {PhoenixMetrics, router: BolognesaWeb.Router, endpoint: BolognesaWeb.Endpoint},
      {EctoMetrics, repos: [Bolognesa.Repo]},
      {Plugins.Oban, poll_rate: 60_000},
      LiveViewMetrics,
      PlaybackMetrics,
      OperationalMetrics
    ]
  end

  @impl true
  def dashboards do
    Enum.map(~w(application beam phoenix ecto oban), &{:prom_ex, &1 <> ".json"})
  end
end
