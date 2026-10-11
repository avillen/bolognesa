defmodule BolognesaWeb.Settings.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Settings.Reducer
  @impl true
  def mount(_params, _session, socket), do: {:ok, Reducer.Initialize.call(socket)}
  @impl true
  def handle_event("save", %{"preferences" => params}, socket),
    do: {:noreply, Reducer.Save.call(socket, params)}
end
