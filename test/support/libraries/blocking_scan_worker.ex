defmodule Bolognesa.Libraries.Support.BlockingScanWorker do
  @moduledoc false
  use Oban.Worker, queue: :library_scans, max_attempts: 3

  alias Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository
  alias Bolognesa.Libraries.Support.{ControlledFileDiscovery, UnavailableScanRepository}

  @impl Oban.Worker
  def timeout(%Oban.Job{args: %{"mode" => "timeout"}}), do: 100
  def timeout(_job), do: :infinity

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    owner = args |> Map.fetch!("owner") |> String.to_charlist() |> :erlang.list_to_pid()
    ControlledFileDiscovery.configure(owner)
    send(owner, {:engine_started, job.id, self(), job.attempt})

    repository =
      if args["mode"] == "storage", do: UnavailableScanRepository, else: EctoScanRepository

    ScanWorker.perform(job, repository, ControlledFileDiscovery)
  end

  @spec telemetry([atom()], map(), map(), {pid(), atom()}) :: :ok
  def telemetry(event, _measurements, %{conf: %{name: name}} = metadata, {owner, name}) do
    send(owner, {:engine_event, event, metadata})
    :ok
  end

  def telemetry(_event, _measurements, _metadata, _config), do: :ok
end
