defmodule BolognesaWeb.Movie.Show.Reducer.MarkWatched do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  alias Bolognesa.Movies

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{detail: detail}} = socket) do
    case Movies.mark_watched(socket.assigns.current_scope.actor, detail.movie.id) do
      :ok ->
        socket
        |> assign(:watched_at, DateTime.utc_now())
        |> put_flash(:info, gettext("Marcado como visto."))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("No se pudo actualizar el estado de visto."))
    end
  end
end
