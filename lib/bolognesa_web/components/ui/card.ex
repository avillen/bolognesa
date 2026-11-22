defmodule BolognesaWeb.Components.UI.Card do
  @moduledoc """
  Card container for content items, copied from SaladUI. Its header, title,
  description, content and footer parts are left out until a screen needs them.
  """
  use BolognesaWeb.Components.UI, :component

  @doc """
  Renders a card container.

  ## Examples:

      <Card.card tag="article" class="music-recent-card">...</Card.card>
  """

  attr :class, :string, default: nil
  # Bolognesa addition: keep list semantics, e.g. `tag="article"` for content items.
  attr :tag, :string, default: "div", values: ~w(div article section li)
  slot :inner_block, required: true
  attr :rest, :global

  def card(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={
        classes(["rounded-xl border border-border bg-card text-card-foreground shadow-sm", @class])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end
end
