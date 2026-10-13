defmodule Bolognesa.Music.Application.Dto.Track do
  @moduledoc "Music list item including processing state."
  defstruct [
    :id,
    :file_id,
    :title,
    :artist,
    :album,
    :duration_ms,
    :state,
    :failure_reason,
    :disc_number,
    :track_number
  ]

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          file_id: pos_integer(),
          title: String.t(),
          artist: String.t() | nil,
          album: String.t() | nil,
          duration_ms: non_neg_integer() | nil,
          state: :pending | :ready | :inspection_failed | :import_failed,
          failure_reason: atom() | nil,
          disc_number: pos_integer() | nil,
          track_number: pos_integer() | nil
        }
  @spec from_domain(Bolognesa.Music.Domain.ReadModels.TrackRow.t()) :: t()
  def from_domain(row), do: struct!(__MODULE__, Map.from_struct(row))
end
