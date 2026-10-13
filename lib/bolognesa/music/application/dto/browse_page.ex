defmodule Bolognesa.Music.Application.Dto.BrowsePage do
  @moduledoc "Bounded local music browsing projection."
  alias Bolognesa.Music.Application.Dto.BrowseItem
  defstruct [:items, :total, :page, :heading]

  @type t :: %__MODULE__{
          items: [Bolognesa.Music.Application.Dto.BrowseItem.t()],
          total: non_neg_integer(),
          page: pos_integer(),
          heading: String.t() | nil
        }

  @spec from_domain(Bolognesa.Music.Domain.ReadModels.BrowsePage.t()) :: t()
  def from_domain(value),
    do: %__MODULE__{
      items: Enum.map(value.items, &BrowseItem.from_domain/1),
      total: value.total,
      page: value.page,
      heading: value.heading
    }
end
