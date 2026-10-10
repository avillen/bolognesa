defmodule BolognesaWeb.Movie.Review.Reducer.ApplyCorrectionResult do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  alias BolognesaWeb.Movie.Review.Reducer.{Load, SelectFile}

  @spec call(Phoenix.LiveView.Socket.t(), reference(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, request_id, result) do
    if request_id == socket.assigns.correction_request_id do
      socket = assign(socket, :saving?, false)

      case result do
        {:ok, {:ok, _}} ->
          socket
          |> SelectFile.call(nil)
          |> assign(:feedback, "Corrección guardada.")
          |> Load.call()

        _ ->
          assign(socket, :feedback, "No se pudo guardar la corrección.")
      end
    else
      socket
    end
  end
end
