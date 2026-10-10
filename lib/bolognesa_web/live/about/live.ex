defmodule BolognesaWeb.About.Live do
  @moduledoc false
  use BolognesaWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}
end
