defmodule Bolognesa.Identification.Domain.SeriesDetails do
  @moduledoc "Normalized series provider data owned by Identification."
  defstruct [:provider_id, :title, :year, :overview, :poster_path, :backdrop_path]

  @type t :: %__MODULE__{
          provider_id: pos_integer(),
          title: binary(),
          year: integer() | nil,
          overview: binary() | nil,
          poster_path: binary() | nil,
          backdrop_path: binary() | nil
        }
end
