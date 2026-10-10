defmodule BolognesaWeb.Movie.Show.Reducer.SelectVersion do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  @spec call(Phoenix.LiveView.Socket.t(), binary()) :: Phoenix.LiveView.Socket.t()
  def call(socket, file_id_text) do
    with %{versions: versions} <- socket.assigns.movie,
         {file_id, ""} when file_id > 0 <- Integer.parse(file_id_text),
         %{availability: :available} <- Enum.find(versions, &(&1.id == file_id)) do
      socket
      |> assign(:selected_file_id, file_id)
      |> assign(:playback_error, nil)
    else
      _ -> socket
    end
  end
end
