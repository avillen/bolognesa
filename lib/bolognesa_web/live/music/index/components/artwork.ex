defmodule BolognesaWeb.Music.Index.Components.Artwork do
  @moduledoc """
  Generated sleeves and avatars shown until local artwork exists.

  Albums render as a typographic sleeve carrying the Bolognesa mark; artists render
  as a round avatar with their initials. The tone is derived from the identifier so
  the same album or artist keeps a stable look across screens.
  """
  use BolognesaWeb, :html

  @tones 6

  attr :id, :integer, default: nil
  attr :title, :string, default: nil, doc: "nil while the title is loading"
  attr :kind, :atom, values: [:album, :artist], default: :album
  attr :class, :any, default: nil

  @spec artwork(map()) :: Phoenix.LiveView.Rendered.t()
  def artwork(assigns) do
    assigns = assign(assigns, tone: tone(assigns.id), initials: initials(assigns.title))

    ~H"""
    <div
      class={["music-art", @kind == :artist && "music-art-artist", @class]}
      data-tone={@tone}
      aria-hidden="true"
    >
      <span :if={@kind == :artist} class="music-art-initials">{@initials}</span>
      <img
        :if={@kind == :album}
        class="music-art-mark"
        src={~p"/images/bolognesa-cat.svg"}
        alt=""
        width="96"
        height="96"
      />
      <span :if={@kind == :album && @title} class="music-art-title">{@title}</span>
    </div>
    """
  end

  defp tone(id) when is_integer(id), do: rem(id, @tones)
  defp tone(_id), do: 0

  defp initials(title) when not is_binary(title), do: ""

  defp initials(title) do
    title
    |> String.split(~r/[\s\-_]+/u, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end
end
