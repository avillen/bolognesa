defmodule BolognesaWeb.Components.UI.Alert do
  @moduledoc """
  Alert for status and error messages, copied from SaladUI. Its title part is left
  out until a screen needs it.

  ## Examples:

      <Alert.alert variant="destructive">
        <Alert.alert_description>
          <p>There was a problem with your request. Please try again.</p>
        </Alert.alert_description>
      </Alert.alert>
  """
  use BolognesaWeb.Components.UI, :component

  @variant_classes %{
    "default" => "bg-background text-foreground",
    "destructive" =>
      "bg-background border-destructive/50 text-destructive [&>span]:text-destructive"
  }

  @doc """
  Renders an alert container. `variant` is `"default"` or `"destructive"` (errors).
  """
  attr :variant, :string, default: "default", values: ~w(default destructive)
  attr :class, :string, default: nil
  slot :inner_block, required: true
  attr :rest, :global, default: %{}

  @spec alert(map()) :: Phoenix.LiveView.Rendered.t()
  def alert(assigns) do
    assigns = assign(assigns, :variant_class, @variant_classes[assigns.variant])

    ~H"""
    <div
      role="alert"
      data-part="root"
      class={
        classes([
          "relative w-full rounded-lg border border-border p-4 [&>span~*]:pl-7 [&>span+div]:translate-y-[-3px] [&>span]:absolute [&>span]:left-4 [&>span]:top-4",
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

  @doc """
  Renders an alert description.
  """
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec alert_description(map()) :: Phoenix.LiveView.Rendered.t()
  def alert_description(assigns) do
    ~H"""
    <div
      class={
        classes([
          "text-sm [&_p]:leading-relaxed",
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
