defmodule Bolognesa.Catalog.Application.Dto.EpisodeVersion do
  @moduledoc "Public episode version projection."
  alias Bolognesa.Catalog.Domain.EpisodeVersion, as: DomainEpisodeVersion
  defstruct [:id, :availability, :size_bytes, :origin, :needs_review?, :episode_numbers]

  @type t :: %__MODULE__{
          id: DomainEpisodeVersion.id(),
          availability: :available | :missing,
          size_bytes: non_neg_integer(),
          origin: :automatic | :manual,
          needs_review?: boolean(),
          episode_numbers: [pos_integer()]
        }
  @spec from_domain(DomainEpisodeVersion.t()) :: t()
  def from_domain(row),
    do: %__MODULE__{
      id: row.id,
      availability: row.availability,
      size_bytes: row.size_bytes,
      origin: row.origin,
      needs_review?: row.needs_review?,
      episode_numbers: row.episode_numbers
    }
end
