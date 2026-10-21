defmodule BolognesaWeb.LiveSupport.PlaybackControl do
  @moduledoc "Coordinates authorized playback preparation and temporary sessions for the UI."
  alias Bolognesa.Playback
  alias BolognesaWeb.LiveSupport.PlaybackState

  @spec prepare(Phoenix.LiveView.Socket.t(), pos_integer()) :: Phoenix.LiveView.Socket.t()
  def prepare(socket, file_id) do
    actor = socket.assigns.current_scope.actor
    content_ref = socket.assigns.content_ref
    stop_previous(socket, :version_selected)

    case Playback.video_delivery(actor, content_ref, file_id) do
      {:ok, :direct, _source} -> prepare_direct(socket, file_id)
      {:ok, _profile, _source} -> start_compatible(socket, file_id, 0, :auto)
      {:error, reason} -> PlaybackState.preparation_failed(socket, reason)
    end
  end

  @spec start_compatible(
          Phoenix.LiveView.Socket.t(),
          pos_integer(),
          non_neg_integer(),
          :auto | :video
        ) ::
          Phoenix.LiveView.Socket.t()
  def start_compatible(socket, file_id, offset_ms, mode) do
    actor = socket.assigns.current_scope.actor
    content_ref = socket.assigns.content_ref

    case Playback.start_video_compatible(actor, content_ref, file_id, offset_ms, mode) do
      {:ok, session} ->
        Process.send_after(self(), {:compatible_poll, session.id}, 250)
        PlaybackState.preparing(socket, session)

      {:error, reason} ->
        PlaybackState.preparation_failed(socket, reason, :compatible)
    end
  end

  @spec stop_previous(
          Phoenix.LiveView.Socket.t(),
          Bolognesa.Playback.Infrastructure.TranscodeManager.stop_reason()
        ) :: :ok | {:error, :forbidden}
  def stop_previous(socket, reason) do
    case socket.assigns.compatible_session do
      nil ->
        :ok

      session ->
        Playback.stop_video_compatible(socket.assigns.current_scope.actor, session.id, reason)
    end
  end

  defp prepare_direct(socket, file_id) do
    case Playback.prepare_video(
           socket.assigns.current_scope.actor,
           socket.assigns.content_ref,
           file_id
         ) do
      :ok -> PlaybackState.direct(socket, file_id)
      {:error, reason} -> PlaybackState.preparation_failed(socket, reason)
    end
  end
end
