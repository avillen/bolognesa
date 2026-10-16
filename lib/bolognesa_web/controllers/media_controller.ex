defmodule BolognesaWeb.MediaController do
  use BolognesaWeb, :controller

  alias Bolognesa.Playback
  alias BolognesaWeb.MediaDelivery
  alias BolognesaWeb.MediaMime

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"movie_id" => entry_text, "file_id" => file_text}),
    do: serve_entry(conn, :movie, entry_text, file_text)

  @spec episode(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def episode(conn, %{"episode_id" => entry_text, "file_id" => file_text}),
    do: serve_entry(conn, :episode, entry_text, file_text)

  defp serve_entry(conn, kind, entry_text, file_text) do
    actor = conn.assigns.current_scope.actor

    with {:ok, movie_id} <- positive_id(entry_text),
         {:ok, file_id} <- positive_id(file_text),
         {:ok, source} <- Playback.start(actor, {kind, movie_id}, file_id),
         {:ok, mime_type} <- MediaMime.for_path(source.relative_path) do
      MediaDelivery.serve(conn, source, mime_type)
    else
      {:error, reason} -> MediaDelivery.error_response(conn, reason)
    end
  end

  defp positive_id(text) do
    case Integer.parse(text) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
