defmodule BolognesaWeb.Components.UI.Helpers do
  @moduledoc false

  alias TwMerge.Config

  # Adapted from SaladUI: shadcn's `accent` (subtle hover surface) is `secondary` here,
  # because `accent` is Bolognesa's coral brand colour. Sizes keep 44px touch and remote
  # targets; focus uses the app-wide outline.
  @variants %{
    variant: %{
      "default" => "bg-primary text-primary-foreground shadow-sm hover:bg-primary/90",
      "play" =>
        "bg-primary text-primary-foreground shadow-lg shadow-primary/30 hover:bg-accent-hover disabled:shadow-none transition motion-safe:hover:scale-105 motion-reduce:transition-none",
      "destructive" =>
        "bg-destructive text-destructive-foreground shadow-xs hover:bg-destructive/90",
      "outline" =>
        "border border-input bg-transparent text-foreground hover:bg-secondary hover:text-secondary-foreground",
      "secondary" => "bg-secondary text-secondary-foreground shadow-xs hover:bg-secondary/80",
      "ghost" => "hover:bg-secondary hover:text-secondary-foreground",
      "subtle" =>
        "border border-border text-muted-foreground hover:bg-secondary hover:text-secondary-foreground",
      # The global focus outline is unlayered, so its offset needs `!` to win.
      "nav" =>
        "justify-start gap-2.5 whitespace-normal px-3 text-[13px] font-normal text-muted-foreground hover:bg-secondary hover:text-foreground aria-[current=page]:bg-primary/15 aria-[current=page]:text-foreground aria-[current=page]:ring-1 aria-[current=page]:ring-inset aria-[current=page]:ring-primary/30 focus-visible:outline-offset-2! motion-reduce:transition-none",
      "link" => "text-primary underline-offset-4 hover:underline"
    },
    size: %{
      "default" => "min-h-11 px-4 py-2",
      "sm" => "min-h-11 px-3 text-xs",
      "lg" => "min-h-12 px-6 text-base",
      "icon" => "size-11",
      # Shorthand for the most common round control: `icon` size with the `pill` shape.
      "round" => "size-11 rounded-full"
    },
    shape: %{
      "default" => "",
      "pill" => "rounded-full"
    }
  }

  @default_variants %{
    variant: "default",
    size: "default",
    shape: "default"
  }

  @doc """
  Classes for a button look, also usable on links. Supports three variant kinds:
  - size: `default|sm|lg|icon|round`
  - variant: `default|play|destructive|outline|secondary|ghost|subtle|nav|link`
  - shape: `default|pill`

  `extra` classes are merged with TwMerge, so a conflicting utility (such as
  `px-3` or `whitespace-normal`) replaces the variant's own instead of losing to
  Tailwind's stylesheet order.
  """
  @spec button_variant(map(), String.t() | [String.t() | nil] | nil) :: String.t()
  def button_variant(props \\ %{}, extra \\ nil) do
    variants = Map.take(props, ~w(variant size shape)a)
    variants = Map.merge(@default_variants, variants)

    variation_classes = Enum.map_join(variants, " ", fn {key, value} -> @variants[key][value] end)

    shared_classes =
      "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-lg text-sm font-semibold transition-colors disabled:pointer-events-none disabled:opacity-50"

    classes([shared_classes, variation_classes, extra])
  end

  @doc """
  Joins classes with TwMerge, so a later conflicting utility wins.
  """
  @spec classes([String.t() | [String.t() | nil] | nil]) :: String.t()
  def classes(input) do
    TwMerge.merge(input, tw_merge_config())
  end

  # TwMerge.merge/1 rebuilds its whole config on every call (~170µs) before its cache
  # lookup; build it once instead.
  defp tw_merge_config do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        config = Config.config()
        :persistent_term.put(__MODULE__, config)
        config

      config ->
        config
    end
  end
end
