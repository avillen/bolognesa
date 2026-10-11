defmodule Bolognesa.Catalog.Domain.Series do
  @moduledoc "Catalog-owned series read model."
  defstruct [:id, :provider, :provider_id, :title, :year, :overview, :poster_path, :backdrop_path]
  @type id :: pos_integer()
  @type count :: non_neg_integer()
  @type t :: %__MODULE__{
          id: id(),
          provider: :tmdb,
          provider_id: pos_integer(),
          title: binary(),
          year: integer() | nil,
          overview: binary() | nil,
          poster_path: binary() | nil,
          backdrop_path: binary() | nil
        }
end
