defmodule Bolognesa.Music.Application.Dto.TrackPage do
  @moduledoc "Bounded music page."
  alias Bolognesa.Music.Application.Dto.Track
  defstruct items: [], total: 0, page: 1, page_size: 50

  @type t :: %__MODULE__{
          items: [Track.t()],
          total: non_neg_integer(),
          page: pos_integer(),
          page_size: pos_integer()
        }
  @spec from_domain(Bolognesa.Music.Domain.ReadModels.TrackPage.t()) :: t()
  def from_domain(page),
    do: %__MODULE__{
      items: Enum.map(page.items, &Track.from_domain/1),
      total: page.total,
      page: page.page,
      page_size: page.page_size
    }
end
