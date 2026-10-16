defmodule BolognesaWeb.Series.Review.Reducer.Save do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  alias Bolognesa.Series
  alias BolognesaWeb.Series.Review.AsyncRequest

  @spec call(
          Phoenix.LiveView.Socket.t(),
          Bolognesa.Series.Application.UseCases.CorrectSeriesIdentification.choice()
        ) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{saving?: true}} = socket, _), do: socket

  def call(%{assigns: %{selected_item: nil}} = socket, _),
    do: assign(socket, feedback: gettext("Selecciona un archivo."))

  def call(socket, choice) do
    actor = socket.assigns.current_scope.actor
    id = socket.assigns.selected_file_id

    socket
    |> assign(saving?: true, feedback: nil)
    |> AsyncRequest.start(:correction, fn -> Series.correct(actor, id, choice) end)
  end
end
