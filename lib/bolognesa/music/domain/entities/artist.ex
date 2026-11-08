defmodule Bolognesa.Music.Domain.Entities.Artist do
  @moduledoc "Local musical artist."

  @type id :: pos_integer()

  @type t :: %__MODULE__{
          id: id(),
          library_id: pos_integer(),
          name: String.t(),
          normalized_name: String.t()
        }

  defstruct [:id, :library_id, :name, :normalized_name]
end
