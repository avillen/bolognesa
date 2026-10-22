defmodule BolognesaWeb.LiveSupport.PlaybackControl do
  @moduledoc "Coordinates authorized playback preparation and temporary sessions for the UI."
  alias Bolognesa.Playback
  alias BolognesaWeb.LiveSupport.PlaybackState

  @spec select_version(Phoenix.LiveView.Socket.t(), pos_integer()) :: Phoenix.LiveView.Socket.t()
  def select_version(socket, file_id) do
    with %{versions: versions} <- socket.assigns.detail,
         true <- file_id > 0,
         %{availability: :available} <- Enum.find(versions, &(&1.id == file_id)) do
      prepare(socket, file_id)
    else
      _ -> socket
    end
  end

  defp prepare(socket, file_id) do
    actor = socket.assigns.current_scope.actor
    content_ref = socket.assigns.content_ref

    case Playback.prepare_video(actor, content_ref, file_id) do
      {:ok, :direct} ->
        stop_transcode(socket, :version_selected)
        PlaybackState.direct(socket, file_id)

      {:ok, :transcode, session} ->
        preparing(socket, session)

      {:error, reason} ->
        PlaybackState.preparation_failed(socket, reason)
    end
  end

  @spec start_transcode(
          Phoenix.LiveView.Socket.t(),
          pos_integer(),
          non_neg_integer(),
          :auto | :full_transcode,
          Bolognesa.Playback.Infrastructure.TranscodeManager.stop_reason() | :session_replaced
        ) ::
          Phoenix.LiveView.Socket.t()
  def start_transcode(
        socket,
        file_id,
        offset_ms,
        strategy_override,
        replace_reason \\ :session_replaced
      ) do
    actor = socket.assigns.current_scope.actor
    content_ref = socket.assigns.content_ref

    case Playback.start_video_transcode(
           actor,
           content_ref,
           file_id,
           offset_ms,
           strategy_override,
           replace_reason
         ) do
      {:ok, session} ->
        preparing(socket, session)

      {:error, reason} ->
        PlaybackState.preparation_failed(socket, reason)
    end
  end

  @spec stop_transcode(
          Phoenix.LiveView.Socket.t(),
          Bolognesa.Playback.Infrastructure.TranscodeManager.stop_reason()
        ) :: :ok | {:error, :forbidden}
  def stop_transcode(socket, reason) do
    case socket.assigns.transcode_session do
      nil ->
        :ok

      session ->
        Playback.stop_video_transcode(socket.assigns.current_scope.actor, session.id, reason)
    end
  end

  defp preparing(socket, session) do
    Process.send_after(self(), {:transcode_poll, session.id}, 250)
    PlaybackState.preparing(socket, session)
  end
end
