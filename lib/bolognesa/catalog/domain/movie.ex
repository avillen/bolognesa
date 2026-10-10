defmodule Bolognesa.Catalog.Domain.Movie do
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

  @type id :: pos_integer()
  @type provider :: :tmdb
  @type t :: %__MODULE__{
          id: id(),
          provider: provider(),
          provider_id: pos_integer(),
          title: binary(),
          original_title: binary() | nil,
          year: integer() | nil,
          overview: binary() | nil,
          poster_path: binary() | nil,
          backdrop_path: binary() | nil
        }
end
