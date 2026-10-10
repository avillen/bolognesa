defmodule Bolognesa.Playback.Domain.TechnicalTrack do
  @moduledoc "A playback-owned projection of an inspected track."

  @type t :: %__MODULE__{kind: :video | :audio | :subtitle, codec: String.t() | nil}
  defstruct [:kind, :codec]
end
