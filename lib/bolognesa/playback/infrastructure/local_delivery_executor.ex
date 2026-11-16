defmodule Bolognesa.Playback.Infrastructure.LocalDeliveryExecutor do
  @moduledoc "Execute a validated plan using the original source or the shared FFmpeg manager."
  @behaviour Bolognesa.Playback.Application.Ports.Services.DeliveryExecutor
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan
  alias Bolognesa.Playback.Infrastructure.LocalMediaFile
  alias Bolognesa.Playback.Infrastructure.TranscodeManager

  @impl true
  def prepare(_actor_id, _ref, _file_id, source, %DeliveryPlan{mode: :direct}, _offset, _reason) do
    with :ok <- LocalMediaFile.validate(source), do: {:ok, :direct}
  end

  def prepare(actor_id, ref, file_id, source, plan, offset_ms, reason) do
    with {:ok, session} <-
           TranscodeManager.start(actor_id, ref, file_id, source, plan, offset_ms, reason) do
      {:ok, :transcode, session}
    end
  end
end
