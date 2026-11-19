defmodule BolognesaWeb.Series.Episode.Reducer.MarkWatched do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  alias Bolognesa.Series
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{detail: detail, active_part: part}} = socket) do
    actor = socket.assigns.current_scope.actor
    id = detail.episode.id
    entry = %SeasonEntry{episode_id: id, part_number: part}

    with :ok <- Series.mark_entries_watched(actor, {:entry, entry}),
         {:ok, watched} <- Series.list_watched_entries(actor, {:episode, id}) do
      socket
      |> assign(:watched_at, Map.new(watched, &{&1.part_number, &1.last_watched_at}))
      |> put_flash(:info, gettext("Marcado como visto."))
    else
      {:error, _reason} ->
        put_flash(socket, :error, gettext("No se pudo actualizar el estado de visto."))
    end
  end
end
