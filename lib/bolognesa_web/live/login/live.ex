defmodule BolognesaWeb.Login.Live do
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Login.Reducers.Initialize

  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}
end
