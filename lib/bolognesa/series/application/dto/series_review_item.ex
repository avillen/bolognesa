defmodule Bolognesa.Series.Application.Dto.SeriesReviewItem do
  @moduledoc "Public series file review row."
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Domain.ReadModels.ReviewEpisode
  alias Bolognesa.Series.Domain.ReadModels.ReviewSeriesFile
  alias Bolognesa.Series.Domain.ValueObjects.SeriesCandidate

  @type t :: %__MODULE__{
          id: pos_integer(),
          file_id: pos_integer(),
          filename: binary(),
          availability: ReviewSeriesFile.availability(),
          state: Identification.state(),
          origin: Identification.origin(),
          failure_reason: binary() | nil,
          series_title: binary() | nil,
          series_provider_id: pos_integer() | nil,
          season_number: non_neg_integer() | nil,
          episode_numbers: [pos_integer()],
          episode_ids: [pos_integer()],
          candidates: [SeriesCandidate.t()]
        }

  defstruct [
    :id,
    :file_id,
    :filename,
    :availability,
    :state,
    :origin,
    :failure_reason,
    :series_title,
    :series_provider_id,
    :season_number,
    episode_numbers: [],
    episode_ids: [],
    candidates: []
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
      origin: file.identification.origin,
      failure_reason: file.identification.failure_reason,
      series_title: if(reference, do: reference.series_title, else: nil),
      series_provider_id: if(reference, do: reference.series_provider_id, else: nil),
      season_number: if(reference, do: reference.season_number, else: nil),
      episode_numbers: Enum.map(episodes, & &1.number),
      episode_ids: Enum.map(episodes, & &1.id),
      candidates: file.candidates
    }
  end
end
