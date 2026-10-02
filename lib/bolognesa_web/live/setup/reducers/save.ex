defmodule BolognesaWeb.Setup.Reducers.Save do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [redirect: 2, put_flash: 3]

  alias Bolognesa.Identity
  alias BolognesaWeb.Setup.Forms.Admin

  def call(socket, params) do
    case Identity.setup_status() do
      {:ok, :closed} ->
        redirect(socket, to: "/login")

      {:ok, :open} ->
        validate_and_save(socket, params)

      {:error, :unavailable} ->
        put_flash(socket, :error, "Servicio temporalmente no disponible. Inténtalo de nuevo.")
    end
  end

  defp validate_and_save(socket, params) do
    changeset = Admin.changeset(params)

    if changeset.valid? do
      save(socket, changeset)
    else
      assign(socket, :form, to_form(%{changeset | action: :insert}))
    end
  end

  defp save(socket, changeset) do
    attrs = Map.take(Ecto.Changeset.apply_changes(changeset), [:name, :email, :password])

    case Identity.install_admin(attrs) do
      {:ok, _actor} ->
        redirect(socket, to: "/login")

      {:error, :setup_closed} ->
        redirect(socket, to: "/login")

      {:error, {:invalid, errors}} ->
        changeset =
          Enum.reduce(errors, changeset, fn {field, message}, acc ->
            Ecto.Changeset.add_error(acc, field, message)
          end)

        assign(socket, :form, to_form(%{changeset | action: :insert}))

      {:error, :unavailable} ->
        put_flash(socket, :error, "Servicio temporalmente no disponible. Inténtalo de nuevo.")
    end
  end
end
