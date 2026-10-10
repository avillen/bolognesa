defmodule BolognesaWeb.OriginalMethod do
  @moduledoc "Preserve the request method before Plug.Head translates HEAD to GET."
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: Plug.Conn.put_private(conn, :original_method, conn.method)
end
