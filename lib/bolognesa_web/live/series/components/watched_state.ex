defmodule BolognesaWeb.Series.Components.WatchedState do
  @moduledoc false
  use BolognesaWeb, :html

  attr :id, :string, required: true

  attr :watched_at, :any,
    default: nil,
    doc: "DateTime of the latest viewing, or nil when unwatched"

  attr :class, :string, default: nil

  @spec watched_state(map()) :: Phoenix.LiveView.Rendered.t()
  def watched_state(assigns) do
    ~H"""
    <p :if={@watched_at} id={@id} class={["text-xs text-muted", @class]}>
      {gettext("Visto")} ·
      <time datetime={Date.to_iso8601(@watched_at)}>{Calendar.strftime(@watched_at, "%d/%m/%Y")}</time>
    </p>
    """
  end
end
