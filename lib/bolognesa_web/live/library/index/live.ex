defmodule BolognesaWeb.Library.Index.Live do
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Library.Index.Reducers

  @impl true
  def mount(_params, _session, socket), do: {:ok, Reducers.Initialize.call(socket)}

  @impl true
  def handle_event("validate", %{"library" => params}, socket),
    do: {:noreply, Reducers.Validate.call(socket, params)}

  def handle_event("save", %{"library" => params}, socket),
    do: {:noreply, Reducers.Save.call(socket, params)}
end
