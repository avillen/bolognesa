defmodule BolognesaWeb.LiveSupport.PlaybackState do
  @moduledoc "Shared presentation transitions for movie and episode playback."
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  alias Bolognesa.Playback
  alias Bolognesa.Playback.Domain.ReadModels.TranscodeSession

  @spec initialize(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def initialize(socket) do
    socket
    |> assign(:selected_file_id, nil)
    |> reset()
  end

  @spec direct(Phoenix.LiveView.Socket.t(), pos_integer()) :: Phoenix.LiveView.Socket.t()
  def direct(socket, file_id) do
    socket
    |> reset()
    |> assign(:selected_file_id, file_id)
  end

  @spec preparing(Phoenix.LiveView.Socket.t(), TranscodeSession.t()) ::
          Phoenix.LiveView.Socket.t()
  def preparing(socket, session) do
    socket
    |> reset()
    |> assign(:selected_file_id, session.file_id)
    |> assign(:transcode_session, session)
    |> assign(:transcode_autoplay?, true)
  end

  @spec ready(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def ready(socket) do
    socket
    |> assign(:transcode_ready?, true)
    |> paused(true)
  end

  @spec paused(Phoenix.LiveView.Socket.t(), boolean()) :: Phoenix.LiveView.Socket.t()
  def paused(socket, paused?), do: assign(socket, :transcode_paused?, paused?)

  @spec preparation_failed(Phoenix.LiveView.Socket.t(), Playback.transcode_reason()) ::
          Phoenix.LiveView.Socket.t()
  def preparation_failed(socket, reason),
    do: fail(socket, message(reason), error_reason(reason))

  @spec transcode_failed(Phoenix.LiveView.Socket.t(), :preparation | :interrupted) ::
          Phoenix.LiveView.Socket.t()
  def transcode_failed(socket, stage) do
    message =
      case stage do
        :preparation -> gettext("No se pudo preparar esta versión. Vuelve a intentarlo.")
        :interrupted -> gettext("La conversión se ha interrumpido. Vuelve a intentarlo.")
      end

    fail(socket, message, "transcode_failed")
  end

  defp reset(socket) do
    socket
    |> assign(:transcode_session, nil)
    |> assign(:transcode_ready?, false)
    |> assign(:transcode_paused?, false)
    |> assign(:transcode_poll_attempts, 0)
    |> assign(:transcode_autoplay?, false)
    |> assign(:playback_error, nil)
    |> assign(:playback_error_reason, nil)
  end

  defp fail(socket, message, reason) do
    socket
    |> assign(:playback_error, message)
    |> assign(:playback_error_reason, reason)
  end

  defp message(reason)
       when reason in [
              :missing,
              :source_changed,
              :source_inaccessible,
              :unreadable,
              :unsafe_entry
            ],
       do: gettext("El archivo ya no está disponible. Revisa la biblioteca y vuelve a escanear.")

  defp message(_), do: gettext("No se pudo preparar esta versión. Vuelve a intentarlo.")

  defp error_reason(reason)
       when reason in [
              :missing,
              :source_changed,
              :source_inaccessible,
              :unreadable,
              :unsafe_entry
            ],
       do: "file_unavailable"

  defp error_reason(_), do: "preparation_failed"
end
