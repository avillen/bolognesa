defmodule BolognesaWeb.UserAuth do
  @moduledoc "Resolve the verified actor for browser and LiveView requests."
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor

  @spec fetch_current_scope(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_scope(conn, _opts) do
    case get_session(conn, :user_token) do
      nil -> assign(conn, :current_scope, nil)
      token -> assign_scope_result(conn, Identity.fetch_actor(token))
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
    |> send_resp(503, "Servicio temporalmente no disponible")
    |> halt()
  end

  @spec require_authenticated_user(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope do
      conn
    else
      case Identity.setup_status() do
        {:ok, :open} -> redirect_and_halt(conn, "/setup")
        {:ok, :closed} -> redirect_and_halt(conn, "/login")
        {:error, :unavailable} -> assign_scope_result(conn, {:error, :unavailable})
      end
    end
  end

  @spec on_mount(:require_authenticated, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:require_authenticated, _params, session, socket) do
    result =
      case session["user_token"] do
        nil -> {:error, :unauthenticated}
        token -> Identity.fetch_actor(token)
      end

    case result do
      {:ok, actor} ->
        {:cont, Phoenix.Component.assign(socket, :current_scope, %{actor: actor})}

      {:error, :unauthenticated} ->
        path = if Identity.setup_status() == {:ok, :open}, do: "/setup", else: "/login"
        {:halt, Phoenix.LiveView.redirect(socket, to: path)}

      {:error, :unavailable} ->
        socket =
          Phoenix.LiveView.put_flash(socket, :error, "Servicio temporalmente no disponible")

        {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
    end
  end

  defp redirect_and_halt(conn, path) do
    conn |> redirect(to: path) |> halt()
  end
end
