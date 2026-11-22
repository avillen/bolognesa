defmodule BolognesaWeb.Music.Index.Components.DetailHeading do
  @moduledoc "Album and artist detail heading."
  use BolognesaWeb, :html

  alias BolognesaWeb.Music.Index.Components.Artwork

  attr :browse_kind, :atom, required: true
  attr :library_params, :map, required: true
  attr :artist_id, :integer, default: nil
  attr :album_id, :integer, default: nil
  attr :active_library_id, :integer, default: nil
  attr :loading?, :boolean, required: true
  attr :heading, :string, default: nil
  attr :album_artist, :string, default: nil
  attr :album_year, :integer, default: nil
  attr :total, :integer, required: true
  attr :error, :any, default: nil

  @spec detail_heading(map()) :: Phoenix.LiveView.Rendered.t()
  def detail_heading(assigns) do
    ~H"""
    <div class={["music-album-heading", @browse_kind == :albums && "music-artist-heading"]}>
      <.link
        :if={@browse_kind == :albums}
        patch={~p"/music?#{Map.put(@library_params, :view, :artists)}"}
        class="music-back"
      ><.icon name="hero-chevron-left" class="size-4" />{gettext("Volver a artistas")}</.link>
      <.link
        :if={@browse_kind == :album}
        patch={
          ~p"/music?#{Map.merge(@library_params, %{view: :albums}) |> then(fn params -> if @artist_id, do: Map.put(params, :artist_id, @artist_id), else: params end)}"
        }
        class="music-back"
      ><.icon name="hero-chevron-left" class="size-4" />{gettext("Volver a álbumes")}</.link>
      <Artwork.artwork
        id={if @browse_kind == :album, do: @album_id, else: @artist_id}
        title={if @loading?, do: nil, else: @heading}
        kind={if @browse_kind == :album, do: :album, else: :artist}
        class="music-detail-art"
      />
      <div class="music-album-copy">
        <h2 :if={!@loading? && @heading} id="music-heading">{@heading}</h2>
        <p :if={@browse_kind == :album && !@loading? && @album_artist} class="music-album-artist">
          {@album_artist}
        </p>
        <p :if={@browse_kind == :album && !@loading?} class="music-album-facts">
          <span :if={@album_year} class="music-album-year">{@album_year}</span>
          <span>{ngettext("%{count} canción", "%{count} canciones", @total, count: @total)}</span>
        </p>
      </div>
      <.album_actions
        :if={@browse_kind == :album && !@error && @total > 0}
        album_id={@album_id}
        active_library_id={@active_library_id}
      />
    </div>
    """
  end

  attr :album_id, :integer, default: nil
  attr :active_library_id, :integer, default: nil

  defp album_actions(assigns) do
    ~H"""
    <div class="music-album-actions">
      <Button.button
        id="play-album"
        type="button"
        size="lg"
        class="rounded-full shadow-lg shadow-primary/30 hover:bg-accent-hover"
        data-music-action="album"
        data-album-id={@album_id}
        data-library-id={@active_library_id}
        aria-label={gettext("Reproducir álbum")}
      ><.icon name="hero-play-solid" class="size-5" />{gettext("Reproducir álbum")}</Button.button>
      <Button.button
        type="button"
        variant="outline"
        size="lg"
        class="rounded-full"
        data-music-action="append-album"
        data-album-id={@album_id}
        data-library-id={@active_library_id}
        aria-label={gettext("Añadir álbum a la cola")}
      ><.icon name="hero-plus" class="size-5" />{gettext("Añadir a la cola")}</Button.button>
    </div>
    """
  end
end
