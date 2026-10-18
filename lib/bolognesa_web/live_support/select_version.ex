defmodule BolognesaWeb.LiveSupport.SelectVersion do
  @moduledoc false
  alias BolognesaWeb.LiveSupport.PlaybackControl

  @spec call(Phoenix.LiveView.Socket.t(), binary()) :: Phoenix.LiveView.Socket.t()
  def call(socket, file_id_text) do
    with %{versions: versions} <- socket.assigns.detail,
         {file_id, ""} when file_id > 0 <- Integer.parse(file_id_text),
         %{availability: :available} <- Enum.find(versions, &(&1.id == file_id)) do
      PlaybackControl.prepare(socket, file_id)
    else
      _ -> socket
    end
  end
end
