defmodule Bolognesa.Playback.Infrastructure.TranscodeManager.Telemetry do
  @moduledoc "Emit `[:bolognesa, :playback, :session, event]` telemetry for a transcode session."
  alias Bolognesa.Infrastructure.Observability.PlaybackEvents
  alias Bolognesa.Playback.Domain.ReadModels.TranscodeSession

  @type event :: :started | :preparation | :exited | :closed

  @spec emit(event(), TranscodeSession.t(), map(), map()) :: :ok
  def emit(event, session, measurements, metadata) do
    fields =
      %{
        session_id: session.id,
        file_id: session.file_id,
        strategy: session.plan.mode,
        transport: session.plan.transport
      }
      |> Map.merge(metadata)
      |> PlaybackEvents.sanitize_delivery_metadata()

    :telemetry.execute([:bolognesa, :playback, :session, event], measurements, fields)
  end
end
