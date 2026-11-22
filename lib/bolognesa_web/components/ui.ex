defmodule BolognesaWeb.Components.UI do
  @moduledoc """
  Components copied from SaladUI 1.0 (shadcn/ui for LiveView) and owned by this app.

  Only the components in use are kept. They style themselves with the semantic
  tokens mapped in `assets/css/app.css`. Call them through module aliases, such as
  `<Button.button>`, because their names overlap with CoreComponents.
  """

  @spec __using__(:component) :: Macro.t()
  defmacro __using__(:component) do
    quote do
      use Phoenix.Component

      import BolognesaWeb.Components.UI.Helpers
    end
  end
end
