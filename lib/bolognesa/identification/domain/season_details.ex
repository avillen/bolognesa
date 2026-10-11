defmodule Bolognesa.Identification.Domain.SeasonDetails do
  @moduledoc "Normalized series provider data owned by Identification."
  defstruct [:provider_id, :series_provider_id, :number, :title, :poster_path, :episodes]

  @type t :: %__MODULE__{
          provider_id: pos_integer(),
          series_provider_id: pos_integer(),
          number: non_neg_integer(),
          title: binary() | nil,
          poster_path: binary() | nil,
          episodes: [Bolognesa.Identification.Domain.EpisodeDetails.t()]
        }
end
