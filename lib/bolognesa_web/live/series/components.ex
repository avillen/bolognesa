defmodule BolognesaWeb.Series.Components do
  @moduledoc "Presentation shared by series and episode details."
  use BolognesaWeb, :html

  attr :id, :string, required: true
  attr :text, :string, required: true

  @spec synopsis(map()) :: Phoenix.LiveView.Rendered.t()
  def synopsis(assigns) do
    ~H"""
    <details id={@id} class="series-synopsis" phx-mounted={JS.ignore_attributes("open")}>
      <summary>
        <span class="series-synopsis-text">{@text}</span>
        <span class="series-read-more">{gettext("Leer más")}</span>
        <span class="series-read-less">{gettext("Leer menos")}</span>
      </summary>
    </details>
    """
  end
end
