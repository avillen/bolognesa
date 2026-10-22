defmodule Bolognesa.Movies.Application.UseCases.CorrectMovieIdentification do
  @moduledoc "Resolve an identification by an administrator's explicit choice."
  alias Bolognesa.Accounts
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Movies.Application.Ports.Providers.MovieProvider
  alias Bolognesa.Movies.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Movies.Domain.Entities.Identification

  @spec call(
          Bolognesa.Accounts.Domain.Entities.AuthenticatedUser.t(),
          pos_integer(),
          :unidentified | {:tmdb, pos_integer()},
          IdentificationRepository.adapter(),
          MovieProvider.adapter()
        ) ::
          {:ok, Identification.t()}
          | {:error,
             :forbidden
             | :not_found
             | :unavailable
             | :invalid_choice
             | :wrong_content_type
             | :source_changed}
  def call(actor, file_id, choice, repository, provider) do
    started = Events.started_at()

    result =
      with :ok <- Accounts.authorize(actor, :admin),
           {:ok, file} <- repository.find_file(file_id),
           :ok <- movie_file(file),
           {:ok, details} <- details(choice, provider) do
        repository.correct(file_id, file.revision, details)
      end

    observe(result, actor, file_id, started)
    normalize(result)
  end

  defp movie_file(%{content_type: :movie}), do: :ok
  defp movie_file(_), do: {:error, :wrong_content_type}

  defp details(:unidentified, _provider), do: {:ok, :unidentified}

  defp details({:tmdb, id}, provider) when is_integer(id) and id > 0 do
    case provider.details(id) do
      {:ok, %{provider_id: ^id} = details} -> {:ok, details}
      {:error, :not_found} -> {:provider_error, :not_found, :not_found, :details}
      {:error, reason} -> {:provider_error, :unavailable, reason, :details}
      _ -> {:provider_error, :unavailable, :invalid_response, :details}
    end
  end

  defp details(_, _provider), do: {:error, :invalid_choice}

  defp observe({:ok, identification}, actor, file_id, started) do
    Events.emit(
      :movies,
      :correction,
      :completed,
      %{user_id: actor.id, file_id: file_id, revision: identification.observed_revision},
      %{duration_ms: Events.elapsed(started)}
    )
  end

  defp observe({:error, :unavailable}, actor, file_id, started) do
    Events.emit(
      :movies,
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
      :movies,
      :correction,
      :stale,
      %{user_id: actor.id, file_id: file_id, reason: :source_changed},
      %{duration_ms: Events.elapsed(started)}
    )
  end

  defp observe({:provider_error, _public_reason, reason, stage}, actor, file_id, started) do
    Events.emit(
      :movies,
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
