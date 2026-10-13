defmodule Bolognesa.Music.Domain.Entities.Artist do
  @moduledoc "Local musical artist."
  defstruct [:id, :library_id, :name, :normalized_name]

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          library_id: pos_integer() | nil,
          name: String.t() | nil,
          normalized_name: String.t() | nil
        }
end
