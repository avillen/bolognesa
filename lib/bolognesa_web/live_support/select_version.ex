defmodule BolognesaWeb.LiveSupport.SelectVersion do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  alias Bolognesa.Playback

  @spec call(Phoenix.LiveView.Socket.t(), binary()) :: Phoenix.LiveView.Socket.t()
  def call(socket, file_id_text) do
    with %{versions: versions} <- socket.assigns.detail,
         {file_id, ""} when file_id > 0 <- Integer.parse(file_id_text),
         %{availability: :available} <- Enum.find(versions, &(&1.id == file_id)) do
      prepare(socket, file_id)
    else
      _ -> socket
    end
  end

  defp prepare(socket, file_id) do
    actor = socket.assigns.current_scope.actor
    catalog_entry_id = socket.assigns.catalog_entry_id
    stop_previous(socket)

    case Playback.delivery(actor, catalog_entry_id, file_id) do
      {:ok, :direct, _source} ->
        prepare_direct(socket, actor, catalog_entry_id, file_id)

      {:ok, _profile, _source} ->
        start_compatible(socket, actor, catalog_entry_id, file_id, 0, :auto)

      {:error, reason} ->
        socket
        |> assign(:playback_error, message(reason))
        |> assign(:playback_error_reason, error_reason(reason))
    end
  end

  @spec start_compatible(
          Phoenix.LiveView.Socket.t(),
          Bolognesa.Identity.Domain.Entities.Actor.t(),
          pos_integer(),
          pos_integer(),
          non_neg_integer(),
          :auto | :video
        ) :: Phoenix.LiveView.Socket.t()
  def start_compatible(socket, actor, catalog_entry_id, file_id, offset_ms, mode) do
    case Playback.start_compatible(actor, catalog_entry_id, file_id, offset_ms, mode) do
      {:ok, session} ->
        Process.send_after(self(), {:compatible_poll, session.id}, 250)

        socket
        |> assign(:selected_file_id, file_id)
        |> assign(:compatible_session, session)
        |> assign(:compatible_ready?, false)
        |> assign(:compatible_paused?, false)
        |> assign(:compatible_poll_attempts, 0)
        |> assign(:compatible_autoplay?, true)
        |> assign(:playback_error, nil)
        |> assign(:playback_error_reason, nil)

      {:error, reason} ->
        socket
        |> assign(:compatible_session, nil)
        |> assign(:compatible_ready?, false)
        |> assign(:playback_error, message(reason))
        |> assign(:playback_error_reason, error_reason(reason))
    end
  end

  @spec stop_previous(Phoenix.LiveView.Socket.t()) :: :ok
  def stop_previous(socket) do
    case socket.assigns.compatible_session do
      nil -> :ok
      session -> Playback.stop_compatible(socket.assigns.current_scope.actor, session.id)
    end
  end

  defp prepare_direct(socket, actor, catalog_entry_id, file_id) do
    case Playback.prepare(actor, catalog_entry_id, file_id) do
      :ok ->
        socket
        |> assign(:selected_file_id, file_id)
        |> assign(:compatible_session, nil)
        |> assign(:compatible_ready?, false)
        |> assign(:compatible_paused?, false)
        |> assign(:compatible_autoplay?, false)
        |> assign(:playback_error, nil)
        |> assign(:playback_error_reason, nil)

      {:error, reason} ->
        socket
        |> assign(:playback_error, message(reason))
        |> assign(:playback_error_reason, error_reason(reason))
    end
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
