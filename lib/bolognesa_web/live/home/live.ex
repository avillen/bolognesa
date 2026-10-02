defmodule BolognesaWeb.Home.Live do
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Home.Reducers.Initialize

  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}
end
