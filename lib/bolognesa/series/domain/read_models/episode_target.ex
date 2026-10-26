defmodule Bolognesa.Series.Domain.ReadModels.EpisodeTarget do
  @moduledoc "An episode and optional physical part to open."
  @type t :: %__MODULE__{
          id: pos_integer(),
          season_id: pos_integer(),
          part_number: pos_integer() | nil
        }
  defstruct [:id, :season_id, :part_number]
end
