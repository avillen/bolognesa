defmodule BolognesaWeb.Components.UI.Badge do
  @moduledoc """
  Badge for short status labels, copied from SaladUI. It renders a `<span>` so it
  can sit inside text, and keeps only the coral-tinted look that screens use; the
  upstream variants are left out until a screen needs them.

  ## Examples:

      <Badge.badge id="movie-selected-1">Seleccionada</Badge.badge>
  """
  use BolognesaWeb.Components.UI, :component

  @doc """
  Renders a badge.
  """
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec badge(map()) :: Phoenix.LiveView.Rendered.t()
  def badge(assigns) do
    ~H"""
    <span
      class={
        classes([
          "inline-flex items-center rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-accent-soft",
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end
end
