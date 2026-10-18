defmodule Bolognesa.Series.Application.UseCases.FetchEpisode.Version do
  @moduledoc "Public episode version projection."
  alias Bolognesa.Series.Domain.ReadModels.EpisodeVersion, as: DomainEpisodeVersion

  @type t :: %__MODULE__{
          id: DomainEpisodeVersion.id(),
          availability: :available | :missing,
          size_bytes: non_neg_integer(),
          origin: :automatic | :manual,
          needs_review?: boolean(),
          episode_numbers: [pos_integer()],
          format: String.t() | nil,
          duration_ms: non_neg_integer() | nil,
          codecs: [String.t()]
        }

  defstruct [
    :id,
    :availability,
    :size_bytes,
    :origin,
    :needs_review?,
    :episode_numbers,
    :format,
    :duration_ms,
    codecs: []
  ]

  @spec from_domain(DomainEpisodeVersion.t()) :: t()
  def from_domain(row),
    do: %__MODULE__{
      id: row.id,
      availability: row.availability,
      size_bytes: row.size_bytes,
      origin: row.origin,
      needs_review?: row.needs_review?,
      episode_numbers: row.episode_numbers,
      format: row.format,
      duration_ms: row.duration_ms,
      codecs: row.codecs
    }
end
