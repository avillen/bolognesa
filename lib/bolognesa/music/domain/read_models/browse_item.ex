defmodule Bolognesa.Music.Domain.ReadModels.BrowseItem do
  @moduledoc "Bounded local music browsing projection."

  @type t :: %__MODULE__{
          id: pos_integer(),
          title: String.t(),
          subtitle: String.t() | nil,
          year: pos_integer() | nil
        }

  defstruct [:id, :title, :subtitle, :year]
end
