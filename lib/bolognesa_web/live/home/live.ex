defmodule BolognesaWeb.Home.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Home.Reducer.Initialize

  @impl true
  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}
end
