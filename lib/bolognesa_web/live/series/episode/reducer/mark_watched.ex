defmodule BolognesaWeb.Series.Episode.Reducer.MarkWatched do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  alias Bolognesa.Series
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{detail: detail, active_part: part}} = socket) do
    entry = %SeasonEntry{episode_id: detail.episode.id, part_number: part}

    case Series.mark_entries_watched(socket.assigns.current_scope.actor, {:entry, entry}) do
      :ok ->
        socket
        |> assign(:watched_parts, MapSet.put(socket.assigns.watched_parts, part))
        |> put_flash(:info, gettext("Marcado como visto."))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("No se pudo actualizar el estado de visto."))
    end
  end
end
