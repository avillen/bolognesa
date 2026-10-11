defmodule Bolognesa.Identification.Domain.SeasonDetails do
  @moduledoc "Normalized series provider data owned by Identification."
  alias Bolognesa.Identification.Domain.EpisodeDetails
  defstruct [:provider_id, :series_provider_id, :number, :title, :poster_path, :episodes]

  @type t :: %__MODULE__{
          provider_id: pos_integer(),
          series_provider_id: pos_integer(),
          number: non_neg_integer(),
          title: binary() | nil,
          poster_path: binary() | nil,
          episodes: [Bolognesa.Identification.Domain.EpisodeDetails.t()]
        }
  @spec new(map()) :: {:ok, t()} | {:error, :invalid_response}
  def new(attrs) do
    value = struct(__MODULE__, attrs)

    if valid_identity?(value) and valid_episodes?(value),
      do: {:ok, value},
      else: {:error, :invalid_response}
  end

  defp valid_identity?(value) do
    is_integer(value.provider_id) and value.provider_id > 0 and
      is_integer(value.series_provider_id) and value.series_provider_id > 0 and
      is_integer(value.number) and value.number >= 0 and
      Enum.all?([value.title, value.poster_path], fn item ->
        is_nil(item) or (is_binary(item) and String.valid?(item))
      end)
  end

  defp valid_episodes?(%{episodes: items, number: number}) when is_list(items) do
    Enum.all?(items, &valid_episode?(&1, number)) and
      Enum.uniq_by(items, & &1.number) == items and Enum.uniq_by(items, & &1.provider_id) == items
  end

  defp valid_episodes?(_), do: false

  defp valid_episode?(%EpisodeDetails{} = item, number),
    do: EpisodeDetails.valid?(item) and item.season_number == number

  defp valid_episode?(_, _), do: false
end
