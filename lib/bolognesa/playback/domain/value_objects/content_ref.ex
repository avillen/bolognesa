defmodule Bolognesa.Playback.Domain.ValueObjects.ContentRef do
  @moduledoc "The explicit identity of a playable video work."
  @type t :: {:movie, pos_integer()} | {:episode, pos_integer()}

  @spec valid?(t()) :: boolean()
  def valid?({kind, id}) when kind in [:movie, :episode] and is_integer(id) and id > 0, do: true
  def valid?(_), do: false
end
