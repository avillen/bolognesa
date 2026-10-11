defmodule Bolognesa.Catalog.Application.Dto.EpisodeVersion do
  @moduledoc "Public episode version projection."
  alias Bolognesa.Catalog.Domain.ReadModels.Series.EpisodeVersion, as: DomainEpisodeVersion

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

  @type t :: %__MODULE__{
          id: DomainEpisodeVersion.id(),
          availability: :available | :missing,
          size_bytes: non_neg_integer(),
          origin: :automatic | :manual,
          needs_review?: boolean(),
          episode_numbers: [pos_integer()],
          format: binary() | nil,
          duration_ms: non_neg_integer() | nil,
          codecs: [binary()]
        }
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
