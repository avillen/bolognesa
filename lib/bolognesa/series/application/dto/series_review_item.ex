defmodule Bolognesa.Series.Application.Dto.SeriesReviewItem do
  @moduledoc "Public series file review row."
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Domain.ReadModels.ReviewEpisode
  alias Bolognesa.Series.Domain.ReadModels.ReviewSeriesFile

  @type t :: %__MODULE__{
          id: pos_integer(),
          file_id: pos_integer(),
          filename: binary(),
          availability: ReviewSeriesFile.availability(),
          state: Identification.state(),
          failure_reason: binary() | nil,
          series_title: binary() | nil,
          season_number: non_neg_integer() | nil,
          episode_numbers: [pos_integer()]
        }

  defstruct [
    :id,
    :file_id,
    :filename,
    :availability,
    :state,
    :failure_reason,
    :series_title,
    :season_number,
    episode_numbers: []
  ]

  @spec from_domain({ReviewSeriesFile.t(), [ReviewEpisode.t()]}) :: t()
  def from_domain({file, episodes}) do
    reference = List.first(episodes)

    %__MODULE__{
      id: file.id,
      file_id: file.id,
      filename: Path.basename(file.relative_path),
      availability: file.availability,
      state: file.identification.state,
      failure_reason: file.identification.failure_reason,
      series_title: if(reference, do: reference.series_title, else: nil),
      season_number: if(reference, do: reference.season_number, else: nil),
      episode_numbers: Enum.map(episodes, & &1.number)
    }
  end
end
