defmodule BolognesaWeb.Series.Episode.Reducer.ApplyAdvanceResult do
  @moduledoc false
  use BolognesaWeb, :verified_routes
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_patch: 2, put_flash: 3]
  alias BolognesaWeb.Series.Navigation

  @spec call(Phoenix.LiveView.Socket.t(), reference(), term()) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, request, result) do
    if socket.assigns[:advance_request] == request do
      finish(socket, result)
    else
      socket
    end
  end

  defp finish(socket, {:ok, {:ok, entry}}),
    do: push_patch(socket, to: ~p"/episodes/#{entry.episode_id}?#{advance_params(socket, entry)}")

  defp finish(socket, {:ok, {:error, :part_unavailable}}),
    do:
      socket
      |> assign(:advance_request, nil)
      |> put_flash(:error, gettext("La siguiente parte no está disponible."))

  defp finish(socket, {:ok, {:error, :not_found}}), do: assign(socket, :advance_request, nil)

  defp finish(socket, _result),
    do:
      socket
      |> assign(:advance_request, nil)
      |> put_flash(:error, gettext("No se encontró el episodio."))

  defp advance_params(
         %{assigns: %{detail: %{season: %{id: season_id}}}} = socket,
         %{
           season_id: season_id
         } = entry
       ),
       do:
         Navigation.episode_target_params(
           socket.assigns.series_params,
           Map.get(socket.assigns.season_params, :page, 1),
           entry
         )

  defp advance_params(socket, entry),
    do: Navigation.episode_target_params(Map.get(socket.assigns, :series_params, %{}), 1, entry)
end
