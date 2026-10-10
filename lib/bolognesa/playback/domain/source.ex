defmodule Bolognesa.Playback.Domain.Source do
  @moduledoc "A physical source authorized for direct playback."

  @type t :: %__MODULE__{
          path: String.t(),
          relative_path: binary(),
          size_bytes: non_neg_integer(),
          modified_at: DateTime.t()
        }

  defstruct [:path, :relative_path, :size_bytes, :modified_at]
end
