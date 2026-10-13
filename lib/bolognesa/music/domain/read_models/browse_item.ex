defmodule Bolognesa.Music.Domain.ReadModels.BrowseItem do
  @moduledoc "Bounded local music browsing projection."
  defstruct [:id, :title, :subtitle, :year]

  @type t :: %__MODULE__{
          id: pos_integer(),
          title: String.t(),
          subtitle: String.t() | nil,
          year: pos_integer() | nil
        }
end
