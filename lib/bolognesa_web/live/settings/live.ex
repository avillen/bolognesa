defmodule BolognesaWeb.Settings.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Settings.Reducer.Initialize
  alias BolognesaWeb.Settings.Reducer.Save
  @impl true
  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}
  @impl true
  def handle_event("save", %{"preferences" => params}, socket),
    do: {:noreply, Save.call(socket, params)}
end
