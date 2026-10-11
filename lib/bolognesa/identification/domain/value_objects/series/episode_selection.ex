defmodule Bolognesa.Identification.Domain.ValueObjects.Series.EpisodeSelection do
  @moduledoc "A validated complete selection of episodes from one season."
  alias Bolognesa.Identification.Domain.ValueObjects.Series.{
    EpisodeDetails,
    SeasonDetails,
    SeriesDetails
  }

  defstruct [:series, :season, :episodes]

  @type t :: %__MODULE__{
          series: SeriesDetails.t(),
          season: SeasonDetails.t(),
          episodes: [EpisodeDetails.t()]
        }
  @type error :: :invalid_selection | :invalid_response | :incomplete_episodes

  @spec new(SeriesDetails.t(), SeasonDetails.t(), [pos_integer()]) ::
          {:ok, t()} | {:error, error()}
  def new(%SeriesDetails{} = series, %SeasonDetails{} = season, numbers) do
    with :ok <- validate_numbers(numbers),
         :ok <- validate_response(series, season),
         {:ok, episodes} <- select_episodes(season.episodes, numbers) do
      {:ok, %__MODULE__{series: series, season: season, episodes: episodes}}
    end
  end

  def new(_, _, _), do: {:error, :invalid_response}

  defp validate_numbers(numbers) when is_list(numbers) do
    if length(numbers) in 1..100 and Enum.all?(numbers, &(is_integer(&1) and &1 > 0)) and
         Enum.uniq(numbers) == numbers, do: :ok, else: {:error, :invalid_selection}
  end

  defp validate_numbers(_), do: {:error, :invalid_selection}

  defp validate_response(series, season) do
    if valid_series?(series) and valid_season?(season, series.provider_id) and
         valid_episode_response?(season), do: :ok, else: {:error, :invalid_response}
  end

  defp valid_series?(series) do
    positive?(series.provider_id) and text?(series.title) and
      (is_nil(series.year) or is_integer(series.year)) and
      optional_texts?(series, [:overview, :poster_path, :backdrop_path])
  end

  defp valid_season?(season, series_id) do
    positive?(season.provider_id) and season.series_provider_id == series_id and
      is_integer(season.number) and season.number >= 0 and
      optional_texts?(season, [:title, :poster_path])
  end

  defp valid_episode_response?(%{episodes: episodes} = season) when is_list(episodes) do
    Enum.all?(episodes, &valid_episode?(&1, season.number)) and
      Enum.uniq_by(episodes, & &1.number) == episodes and
      Enum.uniq_by(episodes, & &1.provider_id) == episodes
  end

  defp valid_episode_response?(_), do: false

  defp valid_episode?(%EpisodeDetails{} = episode, season_number) do
    positive?(episode.provider_id) and positive?(episode.number) and
      episode.season_number == season_number and
      text?(episode.title) and optional_texts?(episode, [:overview, :still_path]) and
      (is_nil(episode.air_date) or is_struct(episode.air_date, Date))
  end

  defp valid_episode?(_, _), do: false

  defp select_episodes(episodes, numbers) do
    by_number = Map.new(episodes, &{&1.number, &1})
    selected = Enum.map(numbers, &Map.get(by_number, &1))
    if Enum.any?(selected, &is_nil/1), do: {:error, :incomplete_episodes}, else: {:ok, selected}
  end

  defp positive?(value), do: is_integer(value) and value > 0

  defp text?(value),
    do:
      is_binary(value) and String.valid?(value) and String.trim(value) != "" and
        byte_size(value) <= 256

  defp optional_texts?(value, fields),
    do:
      Enum.all?(fields, fn key ->
        item = Map.fetch!(value, key)
        is_nil(item) or (is_binary(item) and String.valid?(item))
      end)
end
