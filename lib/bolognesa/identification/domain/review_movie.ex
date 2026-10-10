defmodule Bolognesa.Identification.Domain.ReviewMovie do
  @moduledoc "Movie facts needed by the identification review."

  @type t :: %__MODULE__{id: pos_integer(), title: String.t()}

  defstruct [:id, :title]
end
