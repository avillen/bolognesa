defmodule BolognesaWeb.Home.Reducers.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 2]

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    actor = socket.assigns.current_scope.actor

    socket
    |> assign(:page_title, "Inicio")
    |> assign(:admin_name, actor.name)
    |> assign(:admin_email, actor.email)
    |> assign(:logout_form, to_form(%{}, as: :logout))
  end
end
