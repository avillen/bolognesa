defmodule BolognesaWeb.Player do
  @moduledoc "Shared authorized playback controls for movie and episode pages."
  use BolognesaWeb, :html
  attr :prefix, :string, required: true
  attr :kind, :atom, required: true
  attr :entry_id, :integer, required: true
  attr :selected_file_id, :integer, default: nil
  attr :transcode_session, :any, default: nil
  attr :transcode_ready?, :boolean, required: true
  attr :transcode_paused?, :boolean, required: true
  attr :transcode_autoplay?, :boolean, required: true
  attr :playback_error, :string, default: nil
  attr :playback_error_reason, :string, default: nil
  attr :class, :string, default: "mt-10 space-y-3"
  attr :poster, :string, default: nil
  attr :retry_file_id, :integer, default: nil
  @spec player(map()) :: Phoenix.LiveView.Rendered.t()
  def player(assigns) do
    assigns =
      assigns
      |> assign(:video_id, video_id(assigns))
      |> assign(:video_src, video_src(assigns))

    ~H"""
    <section
      :if={@selected_file_id}
      id={"#{@prefix}-player"}
      class={@class}
      aria-label={gettext("Reproductor")}
    >
      <p
        :if={@transcode_session && !@transcode_ready? && !@playback_error}
        id={"#{@prefix}-playback-preparing"}
        role="status"
        data-session-id={@transcode_session.id}
        class="text-muted"
      >
        {gettext("Preparando versión compatible…")}
      </p>
      <div
        :if={!@playback_error}
        id={"#{@prefix}-video-frame"}
        phx-hook="VideoPlayer"
        data-video-id={@video_id}
        data-file-id={@selected_file_id}
        data-session-id={@transcode_session && @transcode_session.id}
        data-paused-server={to_string(@transcode_paused?)}
        data-autoplay={to_string(!@transcode_session || @transcode_autoplay?)}
        data-offset-ms={@transcode_session && @transcode_session.offset_ms}
        data-duration-ms={@transcode_session && @transcode_session.duration_ms}
        data-src={@video_src}
        class="bolognesa-video-frame"
      >
        <div id={"#{@prefix}-video-ui"} phx-update="ignore">
          <media-i18n lang={Gettext.get_locale(BolognesaWeb.Gettext)}>
            <video
              id={@video_id}
              autoplay={!@transcode_session}
              controls
              playsinline
              preload="metadata"
              src={!@transcode_session && @video_src}
              poster={@poster}
              class="aspect-video w-full bg-black"
            >
              {gettext("Tu navegador no admite la reproducción de vídeo.")}
            </video>
          </media-i18n>
        </div>
      </div>
    </section>
    <p
      :if={@playback_error}
      id={"#{@prefix}-playback-error"}
      role="alert"
      data-reason={@playback_error_reason}
      class="mt-4 rounded-xl border border-red-300/30 bg-red-950/30 p-4 text-sm text-red-100"
    >
      {@playback_error}
    </p>
    <button
      :if={@playback_error && @retry_file_id}
      id={"#{@prefix}-retry-playback"}
      type="button"
      phx-click="play"
      phx-value-file_id={@selected_file_id || @retry_file_id}
      class="series-episode-play mt-3"
    >{gettext("Reintentar reproducción")}</button>
    """
  end

  defp video_id(%{transcode_session: %{id: id}, prefix: prefix}),
    do: "#{prefix}-video-#{id}"

  defp video_id(assigns), do: "#{assigns.prefix}-video-#{assigns.selected_file_id}"

  defp video_src(%{selected_file_id: nil}), do: nil

  defp video_src(%{transcode_session: nil} = assigns),
    do: media_url(assigns.kind, assigns.entry_id, assigns.selected_file_id)

  defp video_src(%{transcode_ready?: true} = assigns),
    do:
      hls_url(
        assigns.kind,
        assigns.entry_id,
        assigns.selected_file_id,
        assigns.transcode_session.id
      )

  defp video_src(_assigns), do: nil

  defp media_url(:movie, id, file), do: ~p"/movies/#{id}/media/#{file}"
  defp media_url(:episode, id, file), do: ~p"/episodes/#{id}/media/#{file}"

  defp hls_url(:movie, id, file, session),
    do: ~p"/movies/#{id}/media/#{file}/hls/#{session}/index.m3u8"

  defp hls_url(:episode, id, file, session),
    do: ~p"/episodes/#{id}/media/#{file}/hls/#{session}/index.m3u8"
end
