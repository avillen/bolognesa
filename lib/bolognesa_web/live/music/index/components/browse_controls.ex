defmodule BolognesaWeb.Music.Index.Components.BrowseControls do
  @moduledoc "Navigation, search and feedback for music browsing."
  use BolognesaWeb, :html

  alias BolognesaWeb.MediaComponents

  attr :browse_kind, :atom, required: true
  attr :library_params, :map, required: true
  attr :artist_id, :integer, default: nil

  @spec navigation(map()) :: Phoenix.LiveView.Rendered.t()
  def navigation(assigns) do
    # Links styled as ghost buttons; aria-current, not ARIA tabs, marks the section.
    assigns =
      assign(
        assigns,
        :link_class,
        button_variant(%{variant: "nav"}, "flex-none")
      )

    ~H"""
    <nav
      aria-label={gettext("Explorar música")}
      class="flex max-w-full gap-0.5 overflow-x-auto max-sm:self-start rounded-xl border border-border bg-card p-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
    >
      <.link
        id="music-home-link"
        patch={~p"/music?#{@library_params}"}
        aria-current={@browse_kind == :home && "page"}
        class={@link_class}
      >{gettext("Inicio")}</.link>
      <.link
        id="music-artists-link"
        patch={~p"/music?#{Map.put(@library_params, :view, :artists)}"}
        aria-current={@browse_kind == :artists && "page"}
        class={@link_class}
      >{gettext("Artistas")}</.link>
      <.link
        id="music-albums-link"
        patch={~p"/music?#{Map.put(@library_params, :view, :albums)}"}
        aria-current={@browse_kind == :albums && !@artist_id && "page"}
        class={@link_class}
      >{gettext("Álbumes")}</.link>
      <.link
        id="music-songs-link"
        patch={~p"/music?#{Map.put(@library_params, :view, :tracks)}"}
        aria-current={@browse_kind == :tracks && "page"}
        class={@link_class}
      >{gettext("Canciones")}</.link>
    </nav>
    """
  end

  attr :form, :any, required: true

  @spec search(map()) :: Phoenix.LiveView.Rendered.t()
  def search(assigns) do
    ~H"""
    <.form
      for={@form}
      id="music-search"
      phx-change="search"
      phx-submit="search"
      class="music-search"
    >
      <.icon name="hero-magnifying-glass" class="music-search-icon size-5" />
      <.input
        field={@form[:query]}
        phx-debounce="300"
        type="search"
        class="music-search-input"
        label={gettext("Buscar canciones, artistas o álbumes")}
        placeholder={gettext("Buscar música")}
      />
      <Button.button
        type="submit"
        variant="ghost"
        class="music-search-submit text-accent-soft"
      >
        {gettext("Buscar")}
      </Button.button>
    </.form>
    """
  end

  attr :loading?, :boolean, required: true
  attr :error, :any, default: nil
  attr :browse_kind, :atom, required: true
  attr :total, :integer, required: true

  @spec feedback(map()) :: Phoenix.LiveView.Rendered.t()
  def feedback(assigns) do
    ~H"""
    <p :if={@loading?} id="music-loading" role="status" class="music-feedback">
      {gettext("Cargando música…")}
    </p>
    <MediaComponents.retry_alert :if={@error} id="music-read-error" retry="refresh">
      <p>{@error}</p>
    </MediaComponents.retry_alert>
    <p
      :if={@browse_kind != :home && !@loading? && !@error && @total == 0}
      id="music-empty"
      class="music-feedback"
    >
      {gettext("No hay resultados. Prueba otra búsqueda o escanea tu biblioteca de música.")}
    </p>
    """
  end
end
