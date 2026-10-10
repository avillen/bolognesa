defmodule Bolognesa.Identification.Domain.FileToIdentify do
  @moduledoc "File name bytes needed to infer an identification title."

  @type t :: %__MODULE__{relative_path: binary()}

  defstruct [:relative_path]
end
