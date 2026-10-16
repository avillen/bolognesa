defmodule Bolognesa.Series.Domain.ValueObjects.EpisodeDetails do
  @moduledoc "Normalized series provider data owned by Identification."

  @type t :: %__MODULE__{
          provider_id: pos_integer(),
          season_number: non_neg_integer(),
          number: pos_integer(),
          title: binary(),
          overview: binary() | nil,
          air_date: Date.t() | nil,
          still_path: binary() | nil
        }

  defstruct [:provider_id, :season_number, :number, :title, :overview, :air_date, :still_path]

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = value) do
    valid_numbers?(value) and valid_title?(value.title) and valid_metadata?(value)
  end

  defp valid_numbers?(value) do
    is_integer(value.provider_id) and value.provider_id > 0 and
      is_integer(value.season_number) and value.season_number >= 0 and
      is_integer(value.number) and value.number > 0
  end

  defp valid_title?(title),
    do:
      is_binary(title) and String.valid?(title) and String.trim(title) != "" and
        byte_size(title) <= 256

  defp valid_metadata?(value) do
    Enum.all?([value.overview, value.still_path], fn item ->
      is_nil(item) or (is_binary(item) and String.valid?(item))
    end) and (is_nil(value.air_date) or is_struct(value.air_date, Date))
  end
end
