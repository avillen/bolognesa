defmodule BolognesaWeb.LiveSupport.PlaybackError do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  @spec call(Phoenix.LiveView.Socket.t(), binary()) :: Phoenix.LiveView.Socket.t()
  def call(socket, file_id_text) do
    if socket.assigns.selected_file_id &&
         Integer.to_string(socket.assigns.selected_file_id) == file_id_text do
      socket
      |> assign(
        :playback_error,
        "El navegador no pudo reproducir esta versión. Prueba otra disponible."
      )
      |> assign(:playback_error_reason, "browser_error")
    else
      socket
    end
  end
end
