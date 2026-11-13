defmodule BolognesaWeb.Music.Index.Components.BrowseCard do
  @moduledoc "An artist or album in the music library."
  use BolognesaWeb, :html

  attr :id, :string, required: true
  attr :item, :any, required: true
  attr :browse_kind, :atom, required: true
  attr :library_params, :map, required: true
  attr :browse_params, :map, required: true

  def browse_card(assigns) do
    ~H"""
    <article id={@id}>
      <.link
        id={"#{if @browse_kind == :artists, do: "artist", else: "album"}-#{@item.id}"}
        patch={
          ~p"/music?#{if @browse_kind == :artists, do: Map.merge(@library_params, %{view: :albums, artist_id: @item.id}), else: Map.merge(@browse_params, %{view: :album, album_id: @item.id})}"
        }
        class="music-group-card"
      >
        <div
          class={["music-group-art", @browse_kind == :artists && "music-artist-art"]}
          aria-hidden="true"
        >
          <div class="music-art-ring"></div>
          <.icon
            name={if @browse_kind == :artists, do: "hero-user", else: "hero-musical-note"}
            class="size-12"
          />
        </div>
        <div class="min-w-0">
          <h2 class="font-semibold break-words">{@item.title}</h2><p
            :if={@item.subtitle}
            class="text-sm text-muted break-words"
          >
            {@item.subtitle}
          </p><p :if={@item.year} class="text-sm text-muted">{@item.year}</p>
        </div>
      </.link>
    </article>
    """
  end
end
