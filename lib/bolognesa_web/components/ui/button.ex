defmodule BolognesaWeb.Components.UI.Button do
  @moduledoc """
  Button copied from SaladUI. Its looks come from `button_variant/2`, which links
  that look like buttons also use.
  """
  use BolognesaWeb.Components.UI, :component

  @doc """
  Renders a button with configurable styles and behaviors.

  ## Attributes

  * `:type` - HTML button type attribute (e.g., "button", "submit")
  * `:class` - Additional CSS classes
  * `:variant` - Visual style variant of the button:
      * `"default"` - Primary action button
      * `"play"` - Coral play button with a glow (music)
      * `"secondary"` - Secondary action button
      * `"destructive"` - Buttons for destructive actions
      * `"outline"` - Button with outline style
      * `"ghost"` - Button with minimal styling
      * `"subtle"` - Quiet bordered button with muted text, for secondary icon controls
      * `"nav"` - Navigation link, highlighted by `aria-current="page"`
      * `"link"` - Button that appears as a link
  * `:size` - Size of the button, all with 44px targets:
      * `"default"` - Standard size
      * `"sm"` - Compact text
      * `"lg"` - Large size
      * `"icon"` - Square button optimized for icons
      * `"round"` - Round icon button (`icon` with the `pill` shape)
  * `:shape` - `"default"` or `"pill"` (fully rounded, for any size)
  * `:rest` - Additional HTML attributes including `disabled`, `form`, `name`, `value`

  ## Examples

      <Button.button>Send</Button.button>
      <Button.button variant="destructive" phx-click="delete">Delete</Button.button>
      <Button.button variant="outline" size="sm">Cancel</Button.button>
      <Button.button variant="ghost" size="round">
        <.icon name="hero-x-mark" />
      </Button.button>
      <Button.button type="submit" phx-disable-with="Saving...">Save Changes</Button.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil

  attr :variant, :string,
    values: ~w(default play secondary destructive outline ghost subtle nav link),
    default: "default",
    doc: "the button variant style"

  attr :size, :string, values: ~w(default sm lg icon round), default: "default"
  attr :shape, :string, values: ~w(default pill), default: "default"
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={button_variant(assigns, ["phx-submit-loading:opacity-75", @class])}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
