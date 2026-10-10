defmodule BolognesaWeb.Setup.Live do
  @moduledoc false
  use BolognesaWeb, :live_view

  alias BolognesaWeb.Setup.Reducers

  @impl true
  def mount(_params, _session, socket), do: {:ok, Reducers.Initialize.call(socket)}

  @impl true
  def handle_event("validate", %{"admin" => params}, socket),
    do: {:noreply, Reducers.Validate.call(socket, params)}

  def handle_event("save", %{"admin" => params}, socket),
    do: {:noreply, Reducers.Save.call(socket, params)}
end
