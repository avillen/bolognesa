defmodule Bolognesa.Series.Domain.ValueObjects.Entry do
  @moduledoc "A catalog episode or one numbered part, including known unavailable entries."
  alias Bolognesa.Series.Domain.ReadModels.Episode

  @type part_number :: 1..100 | nil
  @type t :: %__MODULE__{
          episode_id: Episode.id(),
          part_number: part_number()
        }
  @enforce_keys [:episode_id, :part_number]
  defstruct [:episode_id, :part_number]
end
