defmodule BolognesaWeb.Series.Episode.Reducer.RecordWatchedEntries do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  alias Bolognesa.Series
  alias BolognesaWeb.Params

  @spec call(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def call(socket, %{"attempt_id" => id, "file_id" => text}) when is_binary(id) do
    attempt = socket.assigns.playback

    with false <- socket.assigns.loading?,
         %{id: ^id, phase: :ready, error: nil, file_id: file_id} <- attempt,
         ^file_id <- Params.positive_integer(text),
         false <- socket.assigns.watched_attempt_id == id,
         {:episode, episode_id} <- socket.assigns.content_ref,
         :ok <-
           Series.record_watched_entries(socket.assigns.current_scope.actor, episode_id, file_id) do
      assign(socket, :watched_attempt_id, id)
    else
      _ -> socket
    end
  end

  def call(socket, _params), do: socket
end
