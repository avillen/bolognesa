defmodule Bolognesa.Music.Domain.Entities.Artist do
  @moduledoc "Local musical artist."

  @type t :: %__MODULE__{
          id: pos_integer(),
          library_id: pos_integer(),
          name: String.t(),
          normalized_name: String.t()
        }

  defstruct [:id, :library_id, :name, :normalized_name]
end
