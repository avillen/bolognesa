defmodule Bolognesa.Identification.Domain.ReviewSeriesFile do
  @moduledoc "Physical file and current decision for series review."
  alias Bolognesa.Identification.Domain.{Identification, SeriesCandidate}
  defstruct [:id, :relative_path, :availability, :identification, :candidates]

  @type t :: %__MODULE__{
          id: pos_integer(),
          relative_path: binary(),
          availability: :available | :missing,
          identification: Identification.t(),
          candidates: [SeriesCandidate.t()]
        }
end
