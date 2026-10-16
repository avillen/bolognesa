defmodule Bolognesa.Series.Domain.ReadModels.Season do
  @moduledoc "Catalog-owned season read model."
  alias Bolognesa.Series.Domain.ReadModels.Series
  @type id :: pos_integer()
  @type count :: non_neg_integer()
  @type t :: %__MODULE__{
          id: id(),
          series_id: Series.id(),
          number: non_neg_integer(),
          title: String.t() | nil,
          poster_path: String.t() | nil
        }

  defstruct [:id, :series_id, :number, :title, :poster_path]
end
