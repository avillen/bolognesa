defmodule BolognesaWeb.Plugs.Metrics do
  alias Bolognesa.Infrastructure.Observability.PromEx, as: Metrics
  alias Plug.Conn, as: PlugConn
  alias Plug.Crypto, as: PlugCrypto

  @moduledoc "Serves optional metrics using a runtime bearer credential, outside browser sessions."

  @behaviour Plug

  import Plug.Conn

  alias PromEx.Plug, as: PromExPlug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%PlugConn{request_path: "/metrics"} = conn, _opts) do
    respond(conn, Application.get_env(:bolognesa, :metrics_token))
  end

  def call(conn, _opts), do: conn

  defp respond(conn, token) when is_binary(token) and byte_size(token) > 0 do
    authorize(conn, token, get_req_header(conn, "authorization"))
  end

  defp respond(conn, _token), do: conn |> send_resp(404, "Not Found") |> halt()

  defp authorize(conn, token, ["Bearer " <> supplied]) do
    if PlugCrypto.secure_compare(token, supplied) do
      PromExPlug.call(conn, PromExPlug.init(prom_ex_module: Metrics))
    else
      deny(conn)
    end
  end

  defp authorize(conn, _token, _headers), do: deny(conn)

  defp deny(conn) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> send_resp(401, "Unauthorized")
    |> halt()
  end
end
