defmodule BolognesaWeb.UserAuth do
  use Gettext, backend: BolognesaWeb.Gettext
  @moduledoc "Resolve the verified actor for browser and LiveView requests."
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.Actor

  @spec fetch_current_scope(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_scope(conn, _opts) do
    case get_session(conn, :user_token) do
      nil -> assign(conn, :current_scope, nil)
      token -> assign_scope_result(conn, Accounts.fetch_actor(token))
    end
  end

  @spec assign_scope_result(
          Plug.Conn.t(),
          {:ok, Actor.t()} | {:error, :unauthenticated | :unavailable}
        ) :: Plug.Conn.t()
  def assign_scope_result(conn, {:ok, actor}), do: assign(conn, :current_scope, %{actor: actor})
  def assign_scope_result(conn, {:error, :unauthenticated}), do: assign(conn, :current_scope, nil)

  def assign_scope_result(conn, {:error, :unavailable}) do
    conn
    |> send_resp(503, gettext("Servicio temporalmente no disponible"))
    |> halt()
  end

  @spec require_authenticated_user(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope do
      conn
    else
      redirect_unauthenticated(conn)
    end
  end

  @spec require_admin_user(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_admin_user(conn, _opts) do
    case conn.assigns.current_scope do
      %{actor: %Actor{role: :admin}} -> conn
      _ -> conn |> send_resp(403, "Forbidden") |> halt()
    end
  end

  @spec require_authenticated_media(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_authenticated_media(conn, _opts) do
    if conn.assigns.current_scope do
      conn
    else
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> send_resp(401, "")
      |> halt()
    end
  end

  @spec on_mount(
          :require_authenticated | :require_admin,
          map(),
          map(),
          Phoenix.LiveView.Socket.t()
        ) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:require_authenticated, _params, session, socket) do
    browser =
      if session["browser_locale"] in ["es", "en"], do: session["browser_locale"], else: "es"

    Gettext.put_locale(BolognesaWeb.Gettext, browser)

    result =
      case session["user_token"] do
        nil -> {:error, :unauthenticated}
        token -> Accounts.fetch_actor(token)
      end

    case result do
      {:ok, actor} ->
        {:cont, Phoenix.Component.assign(socket, :current_scope, %{actor: actor})}

      {:error, :unauthenticated} ->
        {:halt, Phoenix.LiveView.redirect(socket, to: unauthenticated_path())}

      {:error, :unavailable} ->
        socket =
          Phoenix.LiveView.put_flash(
            socket,
            :error,
            gettext("Servicio temporalmente no disponible")
          )

        {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
    end
  end

  def on_mount(:require_admin, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, %{assigns: %{current_scope: %{actor: %Actor{role: :admin}}}} = socket} ->
        {:cont, socket}

      {:cont, socket} ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/")}

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  defp redirect_unauthenticated(conn) do
    case Accounts.setup_status() do
      {:ok, :open} -> redirect_and_halt(conn, "/setup")
      {:ok, :closed} -> redirect_and_halt(conn, "/login")
      {:error, :unavailable} -> assign_scope_result(conn, {:error, :unavailable})
    end
  end

  defp unauthenticated_path do
    if Accounts.setup_status() == {:ok, :open}, do: "/setup", else: "/login"
  end

  defp redirect_and_halt(conn, path) do
    conn |> redirect(to: path) |> halt()
  end
end
