defmodule Bolognesa.Identification.Domain.ReadModels.ReviewEpisode do
  @moduledoc "Episode reference owned by identification review."
  defstruct [:id, :number, :season_number, :series_title, :series_provider_id]

  @type t :: %__MODULE__{
          id: pos_integer(),
          number: pos_integer(),
          season_number: non_neg_integer(),
          series_title: binary(),
          series_provider_id: pos_integer()
        }
end
