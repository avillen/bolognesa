defmodule Bolognesa.Movies.Application.Ports.Repositories.IdentificationRepository do
  @moduledoc "Persistence boundary for identification transitions."
  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Domain.ReadModels.FileToIdentify
  alias Bolognesa.Movies.Domain.ValueObjects.MovieCandidate
  alias Bolognesa.Movies.Domain.ValueObjects.MovieDetails

  alias Bolognesa.Movies.Domain.Policies.IdentificationPolicy

  @type reason ::
          :not_found | :unavailable | :wrong_content_type | :source_changed | :manual_locked
  @type failure_reason ::
          IdentificationPolicy.failure_reason() | :attempts_exhausted | :unexpected_failure
  @type adapter :: atom()
  @callback find_file(file_id :: pos_integer()) ::
              {:ok, FileToIdentify.t()} | {:error, :not_found | :unavailable}
  @callback begin_identification(
              file_id :: pos_integer(),
              token :: Identification.token(),
              job_id :: integer() | nil
            ) ::
              {:ok, :stale | FileToIdentify.t()} | {:error, :unavailable}
  @callback complete(
              file_id :: pos_integer(),
              token :: Identification.token(),
              candidates :: [MovieCandidate.t()],
              details :: MovieDetails.t() | nil,
              needs_review? :: boolean()
            ) ::
              :ok | {:ok, :stale} | {:error, reason()}
  @callback fail(
              file_id :: pos_integer(),
              token :: Identification.token(),
              reason :: failure_reason()
            ) ::
              :ok | {:ok, :stale} | {:error, reason()}
  @callback correct(
              file_id :: pos_integer(),
              expected_revision :: pos_integer(),
              choice :: :unidentified | MovieDetails.t()
            ) ::
              {:ok, Identification.t()} | {:error, reason()}
  @callback retry(file_id :: pos_integer()) :: {:ok, Identification.t()} | {:error, reason()}
end
