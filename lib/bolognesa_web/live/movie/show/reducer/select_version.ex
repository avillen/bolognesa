defmodule BolognesaWeb.Movie.Show.Reducer.SelectVersion do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  alias Bolognesa.Playback

  @spec call(Phoenix.LiveView.Socket.t(), binary()) :: Phoenix.LiveView.Socket.t()
  def call(socket, file_id_text) do
    with %{versions: versions} <- socket.assigns.movie,
         {file_id, ""} when file_id > 0 <- Integer.parse(file_id_text),
         %{availability: :available} <- Enum.find(versions, &(&1.id == file_id)) do
      prepare(socket, file_id)
    else
      _ -> socket
    end
  end

  defp prepare(socket, file_id) do
    actor = socket.assigns.current_scope.actor

    case Playback.prepare(actor, socket.assigns.movie.id, file_id) do
      :ok ->
        socket
        |> assign(:selected_file_id, file_id)
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
       do: "El archivo ya no está disponible. Revisa la biblioteca y vuelve a escanear."

  defp message(_), do: "No se pudo preparar esta versión. Vuelve a intentarlo."

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
