defmodule BolognesaWeb.Library.Index.Reducers.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [stream: 4]
  alias Bolognesa.Libraries
  alias BolognesaWeb.Library.Index.Forms.Library

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket =
      socket
      |> assign(:page_title, "Bibliotecas")
      |> assign(:form, to_form(Library.changeset()))
      |> assign(:error, nil)
      |> assign(:success, nil)

    case Libraries.list_libraries(socket.assigns.current_scope.actor) do
      {:ok, libraries} ->
        stream(socket, :libraries, libraries, reset: true)

      {:error, _} ->
        socket
        |> assign(:error, "No se pudieron cargar las bibliotecas. Recarga para reintentar.")
        |> stream(:libraries, [], reset: true)
    end
  end
end
