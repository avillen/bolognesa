defmodule BolognesaWeb.Music.Index.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Music.Index.Forms.Filters
  alias BolognesaWeb.Music.Index.Reducer.{ApplyPage, Load, Play, RetryImport}
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:page, 1)
     |> assign(:total, 0)
     |> assign(:page_size, 50)
     |> assign(:loading?, true)
     |> assign(:error, nil)
     |> assign(:request_id, nil)
     |> assign(:selected, nil)
     |> assign(:audio_error, nil)
     |> assign(:form, to_form(%{"query" => ""}, as: :search))
     |> stream(:tracks, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {query, page} = Filters.from_params(params)
    {:noreply, Load.call(socket, query, page)}
  end

  @impl true
  def handle_async({:music_tracks, request_id}, result, socket),
    do: {:noreply, ApplyPage.call(socket, request_id, result)}

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/music?#{Map.put(socket.assigns.library_params, :query, query)}")}
  end

  def handle_event("play", %{"track_id" => track, "file_id" => file}, socket),
    do: {:noreply, Play.call(socket, track, file)}

  def handle_event("retry-import", %{"file_id" => file}, socket),
    do: {:noreply, RetryImport.call(socket, file)}

  def handle_event("refresh", _params, socket),
    do: {:noreply, Load.call(socket, socket.assigns.query, socket.assigns.page)}

  def handle_event("audio-error", _params, socket),
    do:
      {:noreply,
       assign(
         socket,
         :audio_error,
         gettext("El navegador no pudo reproducir este audio. Prueba otro formato.")
       )}
end
