defmodule Bolognesa.Series.Application.UseCases.CorrectSeriesIdentification do
  @moduledoc "Replace a file's entire episode selection after validating its current revision."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Observability.Events
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
          AuthenticatedUser.t(),
          pos_integer(),
          choice(),
          IdentificationRepository.adapter(),
          SeriesProvider.adapter()
        ) :: {:ok, Identification.t()} | {:error, reason()}
  def call(actor, id, choice, repository, provider) do
    started = Events.started_at()

    result =
      with :ok <- Accounts.authorize(actor, :admin),
           {:ok, file} <- repository.find_file(id),
           :ok <- series_file(file),
           {:ok, selection} <- selection(choice, provider) do
        repository.correct_series(id, file.revision, selection)
      end

    observe(result, actor, id, started)
    normalize(result)
  end

  defp series_file(%{content_type: :series}), do: :ok
  defp series_file(_), do: {:error, :wrong_content_type}
  defp selection(:unidentified, _), do: {:ok, :unidentified}

  defp selection({:tmdb, id, number, numbers}, provider)
       when is_integer(id) and id > 0 and is_integer(number) and number >= 0 and is_list(numbers) do
    with :ok <- valid_numbers(numbers),
         {:ok, series} <- provider_result(provider.details(id), :details),
         :ok <- matching(series.provider_id, id, :details),
         {:ok, season} <- provider_result(provider.season(id, number), :season),
         :ok <- matching(season.number, number, :season) do
      EpisodeSelection.new(series, season, numbers)
    else
      {:provider_error, _, _, _} = error -> error
      {:error, reason} -> {:error, reason}
    end
  end

  defp selection(_, _), do: {:error, :invalid_choice}

  defp provider_result({:error, reason}, stage), do: {:provider_error, reason, reason, stage}
  defp provider_result(result, _stage), do: result
  defp matching(value, value, _stage), do: :ok
  defp matching(_, _, stage), do: {:provider_error, :invalid_response, :invalid_response, stage}

  defp valid_numbers(numbers) do
    if length(numbers) in 1..100 and Enum.all?(numbers, &(is_integer(&1) and &1 > 0)) and
         Enum.uniq(numbers) == numbers, do: :ok, else: {:error, :invalid_selection}
  end

  defp observe({:ok, identification}, actor, file_id, started) do
    Events.emit(
      :series,
      :correction,
      :completed,
      %{user_id: actor.id, file_id: file_id, revision: identification.observed_revision},
      %{duration_ms: Events.elapsed(started)}
    )
  end

  defp observe({:error, :unavailable}, actor, file_id, started) do
    Events.emit(
      :series,
      :correction,
      :failed,
      %{
        user_id: actor.id,
        file_id: file_id,
        reason: :storage_unavailable,
        failure_stage: :persistence
      },
      %{duration_ms: Events.elapsed(started)}
    )
  end

  defp observe({:error, :source_changed}, actor, file_id, started) do
    Events.emit(
      :series,
      :correction,
      :stale,
      %{user_id: actor.id, file_id: file_id, reason: :source_changed},
      %{duration_ms: Events.elapsed(started)}
    )
  end

  defp observe({:provider_error, _public_reason, reason, stage}, actor, file_id, started) do
    Events.emit(
      :series,
      :correction,
      :failed,
      %{user_id: actor.id, file_id: file_id, reason: reason, failure_stage: stage},
      %{duration_ms: Events.elapsed(started)}
    )
  end

  defp observe(_result, _actor, _file_id, _started), do: :ok
  defp normalize({:provider_error, reason, _, _}), do: {:error, reason}
  defp normalize(result), do: result
end
