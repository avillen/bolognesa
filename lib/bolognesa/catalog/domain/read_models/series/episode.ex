defmodule Bolognesa.Catalog.Domain.ReadModels.Series.Episode do
  @moduledoc "Catalog-owned episode read model."
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Season
  @type id :: pos_integer()
  @type count :: non_neg_integer()
  @type t :: %__MODULE__{
          id: id(),
          season_id: Season.id(),
          number: pos_integer(),
          title: String.t(),
          overview: String.t() | nil,
          air_date: Date.t() | nil,
          still_path: String.t() | nil
        }

  defstruct [:id, :season_id, :number, :title, :overview, :air_date, :still_path]
end
