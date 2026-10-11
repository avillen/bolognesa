defmodule BolognesaWeb.Settings.Reducer.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 2]
  use Gettext, backend: BolognesaWeb.Gettext
  alias BolognesaWeb.Settings.Forms.Preferences
  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket
    |> assign(:page_title, gettext("Ajustes"))
    |> assign(
      :form,
      to_form(Preferences.changeset(socket.assigns.current_scope.actor.locale), as: :preferences)
    )
  end
end
