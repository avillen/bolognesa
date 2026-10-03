defmodule Bolognesa.Libraries.Domain.Library do
  @moduledoc "A persisted movie library and its canonical source path."
  defstruct [:id, :name, :path]

  @type id :: pos_integer()
  @type t :: %__MODULE__{id: id(), name: String.t(), path: String.t()}
end
