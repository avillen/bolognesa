defmodule Bolognesa.Catalog.Domain.ReadModels.Series.Series do
  @moduledoc "Catalog-owned series read model."
  @type id :: pos_integer()
  @type count :: non_neg_integer()
  @type t :: %__MODULE__{
          id: id(),
          provider: :tmdb,
          provider_id: pos_integer(),
          title: String.t(),
          year: integer() | nil,
          overview: String.t() | nil,
          poster_path: String.t() | nil,
          backdrop_path: String.t() | nil
        }

  defstruct [:id, :provider, :provider_id, :title, :year, :overview, :poster_path, :backdrop_path]
end
