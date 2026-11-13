defmodule BolognesaWeb.Music.Index.Components.DetailHeading do
  @moduledoc "Album and artist detail heading."
  use BolognesaWeb, :html

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
    <div class="music-album-heading">
      <.link
        :if={@browse_kind == :albums}
        patch={~p"/music?#{Map.put(@library_params, :view, :artists)}"}
        class="music-back"
      >{gettext("Volver a artistas")}</.link>
      <.link
        :if={@browse_kind == :album}
        patch={
          ~p"/music?#{Map.merge(@library_params, %{view: :albums}) |> then(fn params -> if @artist_id, do: Map.put(params, :artist_id, @artist_id), else: params end)}"
        }
        class="music-back"
      >{gettext("Volver a álbumes")}</.link>
      <div class="music-detail-art" aria-hidden="true">
        <.icon name="hero-musical-note" class="size-16" />
      </div>
      <div class="music-album-copy">
        <h2 :if={!@loading? && @heading} id="music-heading">{@heading}</h2>
        <p :if={@browse_kind == :album && !@loading? && @album_artist} class="music-album-artist">
          {@album_artist}
        </p>
        <p :if={@browse_kind == :album && !@loading?}>
          <span :if={@album_year} class="music-album-year">{@album_year} · </span>
          {ngettext("%{count} canción", "%{count} canciones", @total, count: @total)}
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
      <button
        id="play-album"
        type="button"
        data-music-action="album"
        data-album-id={@album_id}
        data-library-id={@active_library_id}
        aria-label={gettext("Reproducir álbum")}
      ><.icon name="hero-play-solid" class="size-5" />{gettext("Reproducir álbum")}</button>
      <button
        type="button"
        data-music-action="append-album"
        data-album-id={@album_id}
        data-library-id={@active_library_id}
        aria-label={gettext("Añadir álbum a la cola")}
      ><.icon name="hero-plus" class="size-5" />{gettext("Añadir a la cola")}</button>
    </div>
    """
  end
end
