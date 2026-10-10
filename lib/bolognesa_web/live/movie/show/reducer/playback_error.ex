defmodule BolognesaWeb.Movie.Show.Reducer.PlaybackError do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  @spec call(Phoenix.LiveView.Socket.t(), binary()) :: Phoenix.LiveView.Socket.t()
  def call(socket, file_id_text) do
    if socket.assigns.selected_file_id &&
         Integer.to_string(socket.assigns.selected_file_id) == file_id_text do
      assign(
        socket,
        :playback_error,
        "No se pudo reproducir esta versión. Prueba otra disponible."
      )
    else
      socket
    end
  end
end
