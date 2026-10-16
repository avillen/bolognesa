defmodule Bolognesa.Series.Domain.ReadModels.ReviewSeriesFile do
  @moduledoc "Physical file and current decision for series review."
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Domain.ValueObjects.SeriesCandidate

  @type availability :: :available | :missing
  @type t :: %__MODULE__{
          id: pos_integer(),
          relative_path: binary(),
          availability: availability(),
          identification: Identification.t(),
          candidates: [SeriesCandidate.t()]
        }

  defstruct [:id, :relative_path, :availability, :identification, :candidates]
end
