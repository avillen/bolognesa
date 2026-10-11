defmodule Bolognesa.Catalog.Domain.ReadModels.Movies.Movie do
  @moduledoc "A catalog movie with a stable internal identity and provider reference."

  defstruct [
    :id,
    :provider,
    :provider_id,
    :title,
    :original_title,
    :year,
    :overview,
    :poster_path,
    :backdrop_path
  ]

  @typedoc "Number of movies matching a catalog query, across all pages."
  @type count :: non_neg_integer()

  @type id :: pos_integer()
  @type provider :: :tmdb
  @type title :: String.t()
  @type year :: integer()
  @type poster_path :: String.t()
  @type t :: %__MODULE__{
          id: id(),
          provider: provider(),
          provider_id: pos_integer(),
          title: title(),
          original_title: binary() | nil,
          year: year() | nil,
          overview: binary() | nil,
          poster_path: poster_path() | nil,
          backdrop_path: binary() | nil
        }
end
