defmodule Bolognesa.Identification.Domain.ReadModels.ReviewSeriesFile do
  @moduledoc "Physical file and current decision for series review."
  alias Bolognesa.Identification.Domain.Entities.Identification
  alias Bolognesa.Identification.Domain.ValueObjects.Series.SeriesCandidate
  defstruct [:id, :relative_path, :availability, :identification, :candidates]

  @type availability :: :available | :missing
  @type t :: %__MODULE__{
          id: pos_integer(),
          relative_path: binary(),
          availability: availability(),
          identification: Identification.t(),
          candidates: [SeriesCandidate.t()]
        }
end
