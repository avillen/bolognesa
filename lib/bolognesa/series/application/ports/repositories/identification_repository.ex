defmodule Bolognesa.Series.Application.Ports.Repositories.IdentificationRepository do
  @moduledoc "Persistence boundary for identification transitions."
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Domain.ReadModels.FileToIdentify
  alias Bolognesa.Series.Domain.ValueObjects.EpisodeSelection
  alias Bolognesa.Series.Domain.ValueObjects.SeriesCandidate

  @type adapter :: module()
  @type review_reason :: Bolognesa.Series.Domain.Policies.IdentificationPolicy.review_reason()
  @type failure_reason ::
          Bolognesa.Series.Domain.Policies.IdentificationPolicy.provider_reason()
          | :attempts_exhausted
          | :unexpected_failure
  @type reason ::
          :not_found | :unavailable | :wrong_content_type | :source_changed | :manual_locked
  @callback find_file(file_id :: pos_integer()) ::
              {:ok, FileToIdentify.t()} | {:error, :not_found | :unavailable}
  @callback complete_series(
              file_id :: pos_integer(),
              token :: Identification.token(),
              candidates :: [SeriesCandidate.t()],
              selection :: EpisodeSelection.t() | nil,
              review_reason :: review_reason() | nil
            ) :: :ok | {:ok, :stale} | {:error, :unavailable}
  @callback correct_series(
              file_id :: pos_integer(),
              expected_revision :: pos_integer(),
              choice :: EpisodeSelection.t() | :unidentified
            ) ::
              {:ok, Identification.t()}
              | {:error, :not_found | :unavailable | :wrong_content_type | :source_changed}
  @callback begin_identification(
              file_id :: pos_integer(),
              token :: Identification.token(),
              job_id :: integer() | nil
            ) ::
              {:ok, :stale | FileToIdentify.t()} | {:error, :unavailable}
  @callback fail(
              file_id :: pos_integer(),
              token :: Identification.token(),
              reason :: failure_reason()
            ) ::
              :ok | {:ok, :stale} | {:error, reason()}
  @callback retry(file_id :: pos_integer()) :: {:ok, Identification.t()} | {:error, reason()}
end
