defmodule BolognesaWeb.Series.Episode.Reducer.LoadWatched do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  alias Bolognesa.Series

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    case Series.list_watched_entries(
           socket.assigns.current_scope.actor,
           {:episode, socket.assigns.detail.episode.id}
         ) do
      {:ok, entries} ->
        assign(socket, :watched_parts, MapSet.new(entries, & &1.season_entry.part_number))

      {:error, _reason} ->
        assign(socket, :watched_parts, nil)
    end
  end
end
