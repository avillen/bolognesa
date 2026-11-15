defmodule BolognesaWeb.MediaController do
  use BolognesaWeb, :controller

  alias Bolognesa.Playback
  alias BolognesaWeb.MediaDelivery
  alias BolognesaWeb.MediaMime
  alias BolognesaWeb.Params

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"movie_id" => entry_text, "file_id" => file_text}),
    do: serve_entry(conn, :movie, entry_text, file_text)

  @spec episode(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def episode(conn, %{"episode_id" => entry_text, "file_id" => file_text}),
    do: serve_entry(conn, :episode, entry_text, file_text)

  defp serve_entry(conn, kind, entry_text, file_text) do
    conn = MediaDelivery.with_resource(conn, kind, file_text)
    actor = conn.assigns.current_scope.actor

    with {:ok, movie_id} <- positive_id(entry_text),
         {:ok, file_id} <- positive_id(file_text),
         {:ok, source} <- Playback.start_video(actor, {kind, movie_id}, file_id),
         {:ok, mime_type} <- MediaMime.for_path(source.relative_path) do
      MediaDelivery.serve(conn, source, mime_type)
    else
      {:error, reason} -> MediaDelivery.error_response(conn, reason)
    end
  end

  defp positive_id(value) do
    case Params.positive_integer(value) do
      nil -> {:error, :not_found}
      id -> {:ok, id}
    end
  end
end
