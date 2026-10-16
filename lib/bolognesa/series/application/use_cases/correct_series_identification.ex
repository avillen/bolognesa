defmodule Bolognesa.Series.Application.UseCases.CorrectSeriesIdentification do
  @moduledoc "Replace a file's entire episode selection after validating its current revision."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Domain.ValueObjects.EpisodeSelection
  @type choice :: :unidentified | {:tmdb, pos_integer(), non_neg_integer(), [pos_integer()]}
  @type reason ::
          :forbidden
          | :not_found
          | :unavailable
          | :invalid_choice
          | :invalid_selection
          | :wrong_content_type
          | :source_changed
          | EpisodeSelection.error()
          | SeriesProvider.reason()

  @spec call(
          Actor.t(),
          pos_integer(),
          choice(),
          IdentificationRepository.adapter(),
          SeriesProvider.adapter()
        ) :: {:ok, Identification.t()} | {:error, reason()}
  def call(actor, id, choice, repository, provider) do
    with :ok <- Identity.authorize(actor, :admin),
         {:ok, file} <- repository.find_file(id),
         :ok <- series_file(file),
         {:ok, selection} <- selection(choice, provider) do
      repository.correct_series(id, file.revision, selection)
    end
  end

  defp series_file(%{content_type: :series}), do: :ok
  defp series_file(_), do: {:error, :wrong_content_type}
  defp selection(:unidentified, _), do: {:ok, :unidentified}

  defp selection({:tmdb, id, number, numbers}, provider)
       when is_integer(id) and id > 0 and is_integer(number) and number >= 0 and is_list(numbers) do
    with :ok <- valid_numbers(numbers),
         {:ok, series} <- provider.details(id),
         true <- series.provider_id == id,
         {:ok, season} <- provider.season(id, number),
         true <- season.number == number do
      EpisodeSelection.new(series, season, numbers)
    else
      false -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp selection(_, _), do: {:error, :invalid_choice}

  defp valid_numbers(numbers) do
    if length(numbers) in 1..100 and Enum.all?(numbers, &(is_integer(&1) and &1 > 0)) and
         Enum.uniq(numbers) == numbers, do: :ok, else: {:error, :invalid_selection}
  end
end
