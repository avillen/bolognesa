defmodule BolognesaWeb.Music.Index.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Music.Index.Forms.Filters
  alias BolognesaWeb.Music.Index.Reducer.{ApplyPage, Load, RetryImport}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:browse_kind, :tracks)
     |> assign(:artist_id, nil)
     |> assign(:album_id, nil)
     |> assign(:heading, nil)
     |> assign(:browse_params, %{})
     |> assign(:query, "")
     |> assign(:page, 1)
     |> assign(:total, 0)
     |> assign(:page_size, 50)
     |> assign(:loading?, true)
     |> assign(:error, nil)
     |> assign(:request_id, nil)
     |> assign(:form, to_form(%{"query" => ""}, as: :search))
     |> stream(:groups, [])
     |> stream(:tracks, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {query, page} = Filters.from_params(params)
    {kind, artist, album} = Filters.browse(params)

    browse_params =
      socket.assigns.library_params
      |> Map.put(:view, kind)
      |> optional(:artist_id, artist)
      |> optional(:album_id, album)

    {:noreply,
     socket
     |> assign(:browse_kind, kind)
     |> assign(:artist_id, artist)
     |> assign(:album_id, album)
     |> assign(:browse_params, browse_params)
     |> Load.call(query, page)}
  end

  @impl true
  def handle_async({:music_tracks, request_id}, result, socket),
    do: {:noreply, ApplyPage.call(socket, request_id, result)}

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/music?#{Map.put(socket.assigns.browse_params, :query, query)}")}
  end

  def handle_event("retry-import", %{"file_id" => file}, socket),
    do: {:noreply, RetryImport.call(socket, file)}

  def handle_event("refresh", _params, socket),
    do: {:noreply, Load.call(socket, socket.assigns.query, socket.assigns.page)}

  defp optional(params, _key, nil), do: params
  defp optional(params, key, id), do: Map.put(params, key, id)
end
