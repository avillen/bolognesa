defmodule BolognesaWeb.Series.Components.ContinueLink do
  @moduledoc "Start, Continue or Replay action that opens a Continue target."
  use BolognesaWeb, :html
  alias BolognesaWeb.Series.Navigation

  attr :id, :string, required: true
  attr :target, :any, required: true
  attr :series_params, :map, required: true
  attr :class, :string, required: true

  @spec continue_link(map()) :: Phoenix.LiveView.Rendered.t()
  def continue_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={
        ~p"/episodes/#{@target.entry.episode_id}?#{Navigation.episode_target_params(@series_params, 1, @target.entry)}"
      }
      class={@class}
    >
      <.icon
        name={if @target.action == :replay, do: "hero-arrow-path", else: "hero-play"}
        class="size-5"
      />
      {action_label(@target)}
    </.link>
    """
  end

  defp action_label(%{action: :start}), do: gettext("Empezar")

  defp action_label(%{action: :continue, entry: entry}),
    do: gettext("Continuar %{entry}", entry: entry_label(entry))

  defp action_label(%{action: :replay, entry: entry}),
    do: gettext("Volver a ver desde %{entry}", entry: entry_label(entry))

  defp entry_label(entry) do
    label = gettext("T%{season}·E%{number}", season: entry.season_number, number: entry.number)

    if entry.part_number,
      do: gettext("%{title} (Parte %{number})", title: label, number: entry.part_number),
      else: label
  end
end
