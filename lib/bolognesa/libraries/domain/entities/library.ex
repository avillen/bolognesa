defmodule Bolognesa.Libraries.Domain.Entities.Library do
  @moduledoc "A persisted library and its canonical source path."

  @type id :: pos_integer()
  @type content_type :: :movie | :series | :music
  @type t :: %__MODULE__{
          id: id(),
          name: String.t(),
          path: String.t(),
          content_type: content_type()
        }

  defstruct [:id, :name, :path, :content_type]
end
