defmodule BolognesaWeb.MediaComponents do
  @moduledoc "Presentation shared by movie, series, and episode details."
  use BolognesaWeb, :html

  attr :id, :string, required: true
  attr :text, :string, required: true

  @spec synopsis(map()) :: Phoenix.LiveView.Rendered.t()
  def synopsis(assigns) do
    ~H"""
    <details id={@id} class="media-expandable-synopsis" phx-mounted={JS.ignore_attributes("open")}>
      <summary>
        <span class="media-expandable-synopsis-text">{@text}</span>
        <span class="media-read-more">{gettext("Leer más")}</span>
        <span class="media-read-less">{gettext("Leer menos")}</span>
      </summary>
    </details>
    """
  end
end
