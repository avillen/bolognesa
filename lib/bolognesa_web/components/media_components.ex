defmodule BolognesaWeb.MediaComponents do
  @moduledoc "Presentation shared by movie, series, episode and music screens."
  use BolognesaWeb, :html

  attr :id, :string, required: true
  attr :text, :string, required: true

  @spec synopsis(map()) :: Phoenix.LiveView.Rendered.t()
  def synopsis(assigns) do
    ~H"""
    <details
      id={@id}
      class="media-expandable-synopsis"
      phx-hook="ExpandableSynopsis"
      phx-mounted={JS.ignore_attributes("open")}
    >
      <summary>
        <span class="media-expandable-synopsis-text">{@text}</span>
        <span class="media-read-more">{gettext("Leer más")}</span>
        <span class="media-read-less">{gettext("Leer menos")}</span>
      </summary>
    </details>
    """
  end

  attr :title, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :search_id, :string, required: true
  attr :search_label, :string, required: true
  attr :options_id, :string, required: true
  slot :inner_block, required: true, doc: "the links inside the library options menu"

  @spec catalog_header(map()) :: Phoenix.LiveView.Rendered.t()
  def catalog_header(assigns) do
    ~H"""
    <header class="media-index-heading">
      <h1 class="media-index-title">{@title}</h1>
      <.form
        for={@form}
        id={@search_id}
        phx-change="search"
        phx-submit="search"
        class="media-search-form"
      >
        <div class="media-search-field">
          <.icon name="hero-magnifying-glass" class="size-5 text-muted" />
          <.input
            field={@form[:query]}
            phx-debounce="300"
            type="search"
            label={@search_label}
            placeholder={gettext("Buscar por título…")}
            class="media-search-input"
          />
        </div>
        <Button.button
          type="submit"
          variant="ghost"
          class="px-3 text-muted-foreground"
          aria-label={@search_label}
        >
          <.icon name="hero-arrow-turn-down-left" class="size-5 sm:hidden" />
          <span class="hidden sm:inline">{gettext("Buscar")}</span>
        </Button.button>
      </.form>
      <details id={@options_id} class="media-library-options">
        <summary
          aria-label={gettext("Opciones de biblioteca")}
          class={
            button_variant(
              %{variant: "subtle", size: "icon"},
              "list-none in-open:bg-secondary in-open:text-secondary-foreground [&::-webkit-details-marker]:hidden"
            )
          }
        >
          <.icon name="hero-ellipsis-horizontal" class="size-5" />
        </summary>
        <div class="media-options-menu">
          {render_slot(@inner_block)}
        </div>
      </details>
    </header>
    """
  end

  attr :id, :string, default: nil
  attr :retry, :string, default: nil, doc: "the event the retry button pushes"
  attr :patch, :string, default: nil, doc: "path to patch to instead of `retry`"
  slot :inner_block, required: true

  @spec retry_alert(map()) :: Phoenix.LiveView.Rendered.t()
  def retry_alert(assigns) do
    ~H"""
    <Alert.alert
      id={@id}
      variant="destructive"
      class="flex flex-wrap items-center justify-between gap-3"
    >
      {render_slot(@inner_block)}
      <.link :if={@patch} patch={@patch} class={button_variant(%{variant: "outline"})}>
        {gettext("Reintentar")}
      </.link>
      <Button.button :if={!@patch} type="button" phx-click={@retry} variant="outline">
        {gettext("Reintentar")}
      </Button.button>
    </Alert.alert>
    """
  end
end
