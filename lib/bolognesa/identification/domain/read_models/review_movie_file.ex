defmodule Bolognesa.Identification.Domain.ReadModels.ReviewMovieFile do
  @moduledoc "Physical file facts needed by the identification review."

  @type availability :: :available | :missing
  @type t :: %__MODULE__{
          id: pos_integer(),
          relative_path: binary(),
          availability: availability()
        }

  defstruct [:id, :relative_path, :availability]
end
