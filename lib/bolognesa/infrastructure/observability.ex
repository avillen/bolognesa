defmodule Bolognesa.Infrastructure.Observability do
  @moduledoc "Own the lightweight log subscriber for application diagnostic events."
  use GenServer
  require Logger

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Infrastructure.Observability.PlaybackEvents

  @events PlaybackEvents.events()
  @metadata [
    :session_id,
    :file_id,
    :profile,
    :offset_ms,
    :reason,
    :failure_stage,
    :termination_reason,
    :resource_type,
    :status,
    :tab_id,
    :diagnostic,
    :position_ms,
    :buffered_ms,
    :stall_duration_ms,
    :paused,
    :visibility,
    :sequence,
    :client_time_ms,
    :media_error
  ]
  # Logger merges process metadata. Override formatter fields even when an event
  # omits them, so unrelated request/process values cannot bypass event validation.
  @empty_operational_fields Map.new(
                              @metadata ++
                                [
                                  :request_id,
                                  :context,
                                  :resource,
                                  :outcome,
                                  :operation,
                                  :result,
                                  :user_id,
                                  :library_id,
                                  :scan_id,
                                  :job_id,
                                  :attempt,
                                  :revision,
                                  :failure_reason,
                                  :files_discovered,
                                  :recovered_count,
                                  :changed_library_count,
                                  :count,
                                  :duration_ms,
                                  :exit_status
                                ],
                              &{&1, nil}
                            )

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    # Also recover an attachment left behind by an untrappable process exit.
    :telemetry.detach(__MODULE__)

    :ok =
      :telemetry.attach_many(
        __MODULE__,
        @events ++ Events.events(),
        &__MODULE__.handle_event/4,
        nil
      )

    {:ok, nil}
  end

  @impl true
  def terminate(_reason, _state), do: :telemetry.detach(__MODULE__)

  @spec exit_reason(term()) :: :normal | :shutdown | :closed | :abnormal
  def exit_reason(:normal), do: :normal
  def exit_reason(:shutdown), do: :shutdown
  def exit_reason({:shutdown, :closed}), do: :closed
  def exit_reason({:shutdown, _detail}), do: :shutdown
  def exit_reason(_reason), do: :abnormal

  @spec handle_event([atom()], map(), map(), nil) :: :ok
  def handle_event(event, measurements, metadata, _config) when event in @events do
    {level, message} = log_message(event, metadata)

    fields =
      @empty_operational_fields
      |> Map.merge(Map.take(metadata, @metadata))
      |> Map.merge(Map.take(measurements, [:duration_ms, :exit_status]))

    Logger.log(level, message, Map.to_list(fields))
  end

  def handle_event(
        [:bolognesa, context, resource, outcome] = event,
        measurements,
        metadata,
        _config
      ) do
    {measurements, metadata} = Events.sanitize(event, measurements, metadata)
    fields = @empty_operational_fields |> Map.merge(metadata) |> Map.merge(measurements)
    fields = Map.merge(fields, %{context: context, resource: resource, outcome: outcome})

    Logger.log(
      Events.level(event, metadata),
      "Bolognesa operational observation",
      Map.to_list(fields)
    )
  end

  defp log_message([:bolognesa, :playback, :session, :exited], %{reason: :failed}),
    do: {:error, "Playback FFmpeg exited"}

  defp log_message([:bolognesa, :playback, :browser, :diagnostic], %{diagnostic: :error}),
    do: {:warning, "Playback browser diagnostic"}

  defp log_message(event, _metadata), do: log_message(event)

  defp log_message([:bolognesa, :playback, :session, :started]),
    do: {:info, "Playback session started"}

  defp log_message([:bolognesa, :playback, :session, :closed]),
    do: {:info, "Playback session closed"}

  defp log_message([:bolognesa, :playback, :session, :exited]),
    do: {:info, "Playback FFmpeg exited"}

  defp log_message([:bolognesa, :playback, :liveview, :terminated]),
    do: {:info, "Playback LiveView terminated"}

  defp log_message([:bolognesa, :playback, :hls, :failed]),
    do: {:warning, "Playback HLS request failed"}

  defp log_message([:bolognesa, :playback, :browser, :diagnostic]),
    do: {:info, "Playback browser diagnostic"}
end
