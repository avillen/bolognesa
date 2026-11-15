defmodule Bolognesa.Series.Domain.ValueObjects.EpisodeSelection do
  @moduledoc "A validated complete selection of episodes from one season."
  alias Bolognesa.Series.Domain.ValueObjects.EpisodeDetails
  alias Bolognesa.Series.Domain.ValueObjects.SeasonDetails
  alias Bolognesa.Series.Domain.ValueObjects.SeriesDetails

  @type t :: %__MODULE__{
          series: SeriesDetails.t(),
          season: SeasonDetails.t(),
          episodes: [EpisodeDetails.t()],
          part_number: pos_integer() | nil
        }
  @type error :: :invalid_selection | :invalid_response | :incomplete_episodes

  defstruct [:series, :season, :episodes, :part_number]

  @spec new(SeriesDetails.t(), SeasonDetails.t(), [pos_integer()], pos_integer() | nil) ::
          {:ok, t()} | {:error, error()}
  def new(series, season, numbers, part_number \\ nil)

  def new(%SeriesDetails{} = series, %SeasonDetails{} = season, numbers, part_number) do
    with :ok <- validate_numbers(numbers),
         :ok <- validate_part(part_number, numbers),
         :ok <- validate_response(series, season),
         {:ok, episodes} <- select_episodes(season.episodes, numbers) do
      {:ok,
       %__MODULE__{series: series, season: season, episodes: episodes, part_number: part_number}}
    end
  end

  def new(_, _, _, _), do: {:error, :invalid_response}

  defp validate_part(nil, _), do: :ok
  defp validate_part(part, [_]) when is_integer(part) and part in 1..100, do: :ok
  defp validate_part(_, _), do: {:error, :invalid_selection}

  @doc "Validates selected episode numbers before any provider lookup."
  @spec validate_numbers([pos_integer()]) :: :ok | {:error, :invalid_selection}
  def validate_numbers(numbers) when is_list(numbers) do
    if length(numbers) in 1..100 and Enum.all?(numbers, &(is_integer(&1) and &1 > 0)) and
         Enum.uniq(numbers) == numbers, do: :ok, else: {:error, :invalid_selection}
  end

  def validate_numbers(_), do: {:error, :invalid_selection}

  defp validate_response(series, season) do
    if valid_series?(series) and SeasonDetails.valid?(season) and
         season.series_provider_id == series.provider_id,
       do: :ok,
       else: {:error, :invalid_response}
  end

  defp valid_series?(series) do
    positive?(series.provider_id) and text?(series.title) and
      (is_nil(series.year) or is_integer(series.year)) and
      Enum.all?([series.overview, series.poster_path, series.backdrop_path], fn item ->
        is_nil(item) or (is_binary(item) and String.valid?(item))
      end)
  end

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
end
