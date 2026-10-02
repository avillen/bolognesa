defmodule BolognesaWeb.Login.Reducers.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [redirect: 2, put_flash: 3]

  alias Bolognesa.Identity
  alias BolognesaWeb.Login.Forms.Login

  def call(socket) do
    socket = assign(socket, :current_scope, nil)

    case Identity.setup_status() do
      {:ok, :open} ->
        redirect(socket, to: "/setup")

      {:ok, :closed} ->
        assign(socket, :form, to_form(Login.changeset()))

      {:error, :unavailable} ->
        socket
        |> assign(:form, to_form(Login.changeset()))
        |> put_flash(:error, "Servicio temporalmente no disponible")
    end
  end
end
