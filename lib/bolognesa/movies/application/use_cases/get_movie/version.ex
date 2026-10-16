defmodule Bolognesa.Movies.Application.UseCases.GetMovie.Version do
  @moduledoc "Physical version fields exposed by a catalog movie detail read."

  alias Bolognesa.Movies.Domain.ReadModels.MovieVersion, as: DomainMovieVersion

  @type t :: %__MODULE__{
          id: DomainMovieVersion.id(),
          availability: :available | :missing,
          size_bytes: non_neg_integer(),
          origin: :automatic | :manual | nil,
          needs_review: boolean()
        }

  defstruct [:id, :availability, :size_bytes, :origin, :needs_review]

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
