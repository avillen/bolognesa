defmodule BolognesaWeb.Components.UI.Alert do
  @moduledoc """
  Alert for status and error messages, copied from SaladUI. Its title and
  description parts are left out: the description's text style lives on the root.

  ## Examples:

      <Alert.alert variant="destructive">
        <p>There was a problem with your request. Please try again.</p>
      </Alert.alert>
  """
  use BolognesaWeb.Components.UI, :component

  @variant_classes %{
    "default" => "text-foreground",
    "destructive" => "border-destructive/50 text-destructive"
  }

  @doc """
  Renders an alert container. `variant` is `"default"` or `"destructive"` (errors).
  """
  attr :variant, :string, default: "default", values: ~w(default destructive)
  attr :class, :string, default: nil
  slot :inner_block, required: true
  attr :rest, :global

  @spec alert(map()) :: Phoenix.LiveView.Rendered.t()
  def alert(assigns) do
    assigns = assign(assigns, :variant_class, @variant_classes[assigns.variant])

    ~H"""
    <div
      role="alert"
      class={
        classes([
          "relative w-full rounded-lg border border-border bg-background p-4 text-sm [&_p]:leading-relaxed",
          @variant_class,
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end
end
