defmodule BolognesaWeb.Movie.Review.Reducer.ApplyCandidatesResult do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  @spec call(Phoenix.LiveView.Socket.t(), reference(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, request_id, result) do
    if request_id == socket.assigns.search_request_id do
      case result do
        {:ok, {:ok, candidates}} ->
          socket |> assign(:searching?, false) |> assign(:candidates, candidates)

        {:ok, {:error, :not_configured}} ->
          socket
          |> assign(:searching?, false)
          |> assign(:feedback, "TMDb sin configurar. Añade TMDB_READ_TOKEN al servidor.")

        _ ->
          socket |> assign(:searching?, false) |> assign(:feedback, "No se pudo buscar en TMDb.")
      end
    else
      socket
    end
  end
end
