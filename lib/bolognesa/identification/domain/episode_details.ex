defmodule Bolognesa.Identification.Domain.EpisodeDetails do
  @moduledoc "Normalized series provider data owned by Identification."
  defstruct [:provider_id, :season_number, :number, :title, :overview, :air_date, :still_path]

  @type t :: %__MODULE__{
          provider_id: pos_integer(),
          season_number: non_neg_integer(),
          number: pos_integer(),
          title: binary(),
          overview: binary() | nil,
          air_date: Date.t() | nil,
          still_path: binary() | nil
        }
end
