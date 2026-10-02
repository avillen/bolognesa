defmodule BolognesaWeb.SessionController do
  use BolognesaWeb, :controller

  alias Bolognesa.Identity

  def create(conn, %{"login" => %{"email" => email, "password" => password}}) do
    case Identity.start_session(email, password) do
      {:ok, token} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:user_token, token)
        |> redirect(to: "/")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Correo o contraseña incorrectos")
        |> redirect(to: "/login")

      {:error, :unavailable} ->
        send_resp(conn, 503, "Servicio temporalmente no disponible")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Correo o contraseña incorrectos")
    |> redirect(to: "/login")
  end

  def delete(conn, _params) do
    case Identity.end_session(get_session(conn, :user_token)) do
      :ok ->
        conn
        |> delete_session(:user_token)
        |> configure_session(drop: true)
        |> redirect(to: "/login")

      {:error, :unavailable} ->
        send_resp(conn, 503, "Servicio temporalmente no disponible")
    end
  end
end
