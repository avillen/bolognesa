defmodule BolognesaWeb.Series.Season.Reducer.MarkSeasonWatchedCoordinator do
  @moduledoc "Marks the season watched and, on success, reloads the page so cards show their dates."
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.LiveView, only: [put_flash: 3]
  alias Bolognesa.Series
  alias BolognesaWeb.Series.Season.Reducer.Load

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    case Series.mark_entries_watched(
           socket.assigns.current_scope.actor,
           {:season, socket.assigns.content_id}
         ) do
      :ok ->
        socket
        |> put_flash(:info, gettext("Temporada marcada como vista."))
        |> Load.call(socket.assigns.content_id, socket.assigns.page)

      {:error, _reason} ->
        put_flash(socket, :error, gettext("No se pudo marcar la temporada."))
    end
  end
end
