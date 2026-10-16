defmodule Bolognesa.Series.Domain.ReadModels.FileToIdentify do
  @moduledoc "File name bytes needed to infer an identification title."

  @type t :: %__MODULE__{
          relative_path: binary(),
          content_type: :movie | :series | :music,
          revision: pos_integer()
        }

  defstruct [:relative_path, :content_type, :revision]
end
