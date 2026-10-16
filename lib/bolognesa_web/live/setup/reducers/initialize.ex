defmodule BolognesaWeb.Setup.Reducers.Initialize do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [redirect: 2, put_flash: 3]

  alias Bolognesa.Accounts
  alias BolognesaWeb.Setup.Forms.Admin

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket = assign(socket, :current_scope, nil)

    case Accounts.setup_status() do
      {:ok, :open} ->
        assign(socket, :form, to_form(Admin.changeset()))

      {:ok, :closed} ->
        redirect(socket, to: "/login")

      {:error, :unavailable} ->
        socket
        |> assign(:form, to_form(Admin.changeset()))
        |> put_flash(:error, gettext("Servicio temporalmente no disponible. Inténtalo de nuevo."))
    end
  end
end
