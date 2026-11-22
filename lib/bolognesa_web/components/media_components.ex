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
      <Alert.alert_description>{render_slot(@inner_block)}</Alert.alert_description>
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
