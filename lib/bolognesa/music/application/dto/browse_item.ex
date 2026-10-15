defmodule Bolognesa.Music.Application.Dto.BrowseItem do
  @moduledoc "Bounded local music browsing projection."

  @type t :: %__MODULE__{
          id: pos_integer(),
          title: String.t(),
          subtitle: String.t() | nil,
          year: pos_integer() | nil
        }

  defstruct [:id, :title, :subtitle, :year]

  @spec from_domain(Bolognesa.Music.Domain.ReadModels.BrowseItem.t()) :: t()
  def from_domain(value), do: struct!(__MODULE__, Map.from_struct(value))
end
