defmodule BolognesaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BolognesaWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active_section, :atom, default: nil

  slot :inner_block, required: true

  @spec app(map()) :: Phoenix.LiveView.Rendered.t()
  def app(assigns) do
    ~H"""
    <div class="app-shell">
      <header class="app-sidebar">
        <.link navigate={~p"/"} class="app-brand">
          <img src={~p"/images/bolognesa-cat.svg"} width="36" height="36" alt="" />
          <span>boloñesa</span>
        </.link>
        <nav aria-label="Navegación principal" class="app-navigation">
          <.link
            navigate={~p"/"}
            class={["app-nav-link", @active_section == :home && "is-active"]}
            aria-current={@active_section == :home && "page"}
          >
            <.icon name="hero-home" class="size-5" /> <span>Inicio</span>
          </.link>
          <.link
            navigate={~p"/movies"}
            class={["app-nav-link", @active_section == :movies && "is-active"]}
            aria-current={@active_section == :movies && "page"}
          >
            <.icon name="hero-film" class="size-5" /> <span>Películas</span>
          </.link>
          <.link
            navigate={~p"/series"}
            id="nav-series"
            class={["app-nav-link", @active_section == :series && "is-active"]}
            aria-current={@active_section == :series && "page"}
          >
            <.icon name="hero-tv" class="size-5" /> <span>Series</span>
          </.link>
          <p class="app-nav-caption">Mi biblioteca</p>
          <.link
            navigate={~p"/libraries"}
            class={["app-nav-link", @active_section == :libraries && "is-active"]}
            aria-current={@active_section == :libraries && "page"}
          >
            <.icon name="hero-folder" class="size-5" /> <span>Bibliotecas</span>
          </.link>
          <.link
            navigate={~p"/about"}
            class={["app-nav-link", @active_section == :about && "is-active"]}
            aria-current={@active_section == :about && "page"}
          >
            <.icon name="hero-information-circle" class="size-5" /> <span>Acerca de</span>
          </.link>
        </nav>
        <p class="app-sidebar-note">Tu cine, en casa.</p>
      </header>
      <main id="app-content" class="app-content">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  @spec flash_group(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
