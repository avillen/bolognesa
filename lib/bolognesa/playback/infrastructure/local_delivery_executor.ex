defmodule Bolognesa.Playback.Infrastructure.LocalDeliveryExecutor do
  @moduledoc "Execute a validated plan using the original source or the shared FFmpeg manager."
  @behaviour Bolognesa.Playback.Application.Ports.Services.DeliveryExecutor
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan
  alias Bolognesa.Playback.Infrastructure.{LocalMediaFile, TranscodeManager}

  @impl true
  def prepare(_actor_id, _ref, _file_id, source, %DeliveryPlan{mode: :direct}, offset_ms, _reason) do
    with :ok <- valid_offset(source, offset_ms),
         :ok <- LocalMediaFile.validate(source),
         do: {:ok, :direct}
  end

  def prepare(actor_id, ref, file_id, source, plan, offset_ms, reason) do
    with {:ok, session} <-
           TranscodeManager.start(actor_id, ref, file_id, source, plan, offset_ms, reason) do
      {:ok, :transcode, session}
    end
  end

  defp valid_offset(source, offset_ms) when is_integer(offset_ms) and offset_ms >= 0 do
    if is_nil(source.duration_ms) or offset_ms <= source.duration_ms,
      do: :ok,
      else: {:error, :invalid_offset}
  end

  defp valid_offset(_, _), do: {:error, :invalid_offset}
end
