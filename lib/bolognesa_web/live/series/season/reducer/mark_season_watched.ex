defmodule BolognesaWeb.Series.Season.Reducer.MarkSeasonWatched do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.LiveView, only: [put_flash: 3]
  alias Bolognesa.Series

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    case Series.mark_entries_watched(
           socket.assigns.current_scope.actor,
           {:season, socket.assigns.content_id}
         ) do
      :ok -> put_flash(socket, :info, gettext("Temporada marcada como vista."))
      {:error, _reason} -> put_flash(socket, :error, gettext("No se pudo marcar la temporada."))
    end
  end
end
