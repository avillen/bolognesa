defmodule BolognesaWeb.Series.Season.Reducer.ApplyResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [stream: 4]
  alias Bolognesa.Series.Application.UseCases.ListEpisodes.Response, as: EpisodePage
  alias Bolognesa.Series.Domain.ReadModels.WatchedEntry
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @type result ::
          {:ok,
           {:ok, EpisodePage.t(), [WatchedEntry.t()]}
           | {:error, :forbidden | :not_found | :invalid_page | :unavailable}}
          | {:exit, term()}
  @spec call(Phoenix.LiveView.Socket.t(), reference(), result()) :: Phoenix.LiveView.Socket.t()
  def call(socket, request, result) do
    if socket.assigns.request_id == request, do: apply_result(socket, result), else: socket
  end

  defp apply_result(socket, {:ok, {:ok, detail, watched}}) do
    watched_at = Map.new(watched, &{&1.season_entry, &1.last_watched_at})

    items =
      Enum.map(detail.items, fn item ->
        %{
          item
          | watched_at:
              watched_at[%SeasonEntry{episode_id: item.id, part_number: item.part_number}]
        }
      end)

    socket
    |> assign(detail: detail, loading?: false, total: detail.total)
    |> stream(:episodes, items, reset: true)
  end

  defp apply_result(socket, _),
    do:
      assign(socket,
        loading?: false,
        error: gettext("No se pudo cargar esta ficha. Vuelve a intentarlo.")
      )
end
