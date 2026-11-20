defmodule BolognesaWeb.Series.Episode.Reducer.UnmarkWatched do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  alias Bolognesa.Series
  alias Bolognesa.Series.Domain.ValueObjects.Entry

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{detail: detail, active_part: part}} = socket) do
    entry = %Entry{episode_id: detail.episode.id, part_number: part}

    case Series.unmark_entry_watched(socket.assigns.current_scope.actor, entry) do
      :ok ->
        socket
        |> assign(:watched_at, Map.delete(socket.assigns.watched_at, part))
        |> put_flash(:info, gettext("Marcado como no visto."))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("No se pudo actualizar el estado de visto."))
    end
  end
end
