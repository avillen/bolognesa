defmodule BolognesaWeb.About.Live do
  use BolognesaWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}
end
