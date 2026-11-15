defmodule BolognesaWeb.Music.Index.Components.BrowseCard do
  @moduledoc "An artist or album in the music library."
  use BolognesaWeb, :html

  alias BolognesaWeb.Music.Index.Components.Artwork

  attr :id, :string, required: true
  attr :item, :any, required: true
  attr :browse_kind, :atom, required: true
  attr :library_params, :map, required: true
  attr :browse_params, :map, required: true

  @spec browse_card(map()) :: Phoenix.LiveView.Rendered.t()
  def browse_card(assigns) do
    ~H"""
    <article id={@id}>
      <.link
        id={"#{if @browse_kind == :artists, do: "artist", else: "album"}-#{@item.id}"}
        patch={
          ~p"/music?#{if @browse_kind == :artists, do: Map.merge(@library_params, %{view: :albums, artist_id: @item.id}), else: Map.merge(@browse_params, %{view: :album, album_id: @item.id})}"
        }
        class={["music-group-card", @browse_kind == :artists && "music-group-card-artist"]}
      >
        <Artwork.artwork
          id={@item.id}
          title={@item.title}
          kind={if @browse_kind == :artists, do: :artist, else: :album}
        />
        <div class="music-group-copy">
          <h2>{@item.title}</h2><p :if={@item.subtitle}>{@item.subtitle}</p><p :if={@item.year}>
            {@item.year}
          </p>
        </div>
      </.link>
    </article>
    """
  end
end
