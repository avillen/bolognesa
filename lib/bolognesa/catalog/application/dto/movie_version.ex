defmodule Bolognesa.Catalog.Application.Dto.MovieVersion do
  @moduledoc "Physical version fields exposed by a catalog movie detail read."

  alias Bolognesa.Catalog.Domain.MovieVersion, as: DomainMovieVersion

  @enforce_keys [:id, :availability, :size_bytes, :origin, :needs_review]
  defstruct [:id, :availability, :size_bytes, :origin, :needs_review]

  @type t :: %__MODULE__{
          id: pos_integer(),
          availability: :available | :missing,
          size_bytes: non_neg_integer(),
          origin: :automatic | :manual | nil,
          needs_review: boolean()
        }

  @spec from_domain(DomainMovieVersion.t()) :: t()
  def from_domain(%DomainMovieVersion{} = version) do
    %__MODULE__{
      id: version.id,
      availability: version.availability,
      size_bytes: version.size_bytes,
      origin: version.origin,
      needs_review: version.needs_review?
    }
  end
end
