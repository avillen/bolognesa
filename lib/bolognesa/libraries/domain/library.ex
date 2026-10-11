defmodule Bolognesa.Libraries.Domain.Library do
  @moduledoc "A persisted library and its canonical source path."
  defstruct [:id, :name, :path, :content_type]

  @type id :: pos_integer()
  @type content_type :: :movie | :series
  @type t :: %__MODULE__{
          id: id(),
          name: String.t(),
          path: String.t(),
          content_type: content_type()
        }
end
