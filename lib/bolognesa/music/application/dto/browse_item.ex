defmodule Bolognesa.Music.Application.Dto.BrowseItem do
  @moduledoc "Bounded local music browsing projection."

  alias Bolognesa.Music.Domain.Entities.Album
  alias Bolognesa.Music.Domain.Entities.Artist

  @type t :: %__MODULE__{
          id: Artist.id() | Album.id(),
          title: String.t(),
          subtitle: String.t() | nil,
          year: pos_integer() | nil,
          last_played_at: DateTime.t() | nil
        }

  defstruct [:id, :title, :subtitle, :year, :last_played_at]

  @spec from_domain(Bolognesa.Music.Domain.ReadModels.BrowseItem.t()) :: t()
  def from_domain(value), do: struct!(__MODULE__, Map.from_struct(value))
end
