defmodule BolognesaWeb.Setup.Live do
  @moduledoc false
  use BolognesaWeb, :live_view

  alias BolognesaWeb.Setup.Reducers.Initialize
  alias BolognesaWeb.Setup.Reducers.Save
  alias BolognesaWeb.Setup.Reducers.Validate

  @impl true
  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}

  @impl true
  def handle_event("validate", %{"admin" => params}, socket),
    do: {:noreply, Validate.call(socket, params)}

  def handle_event("save", %{"admin" => params}, socket),
    do: {:noreply, Save.call(socket, params)}
end
