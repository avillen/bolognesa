defmodule Bolognesa.Identification.Application.Ports.Repositories.IdentificationRepository do
  @moduledoc "Persistence boundary for identification transitions."
  alias Bolognesa.Identification.Domain.Entities.Identification
  alias Bolognesa.Identification.Domain.ReadModels.FileToIdentify

  alias Bolognesa.Identification.Domain.ValueObjects.Movies.{MovieCandidate, MovieDetails}
  alias Bolognesa.Identification.Domain.ValueObjects.Series.{EpisodeSelection, SeriesCandidate}

  @type adapter :: atom()
  @type review_reason ::
          :unusable_name
          | :ambiguous_name
          | :invalid_episode_numbers
          | :too_many_episodes
          | :incomplete_episodes
          | :ambiguous_series
          | :no_match
  @callback find_file(file_id :: pos_integer()) ::
              {:ok, FileToIdentify.t()} | {:error, :not_found | :unavailable}
  @callback complete_series(
              file_id :: pos_integer(),
              token :: binary(),
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
  @callback begin_identification(pos_integer(), binary(), integer() | nil) ::
              {:ok, :stale | FileToIdentify.t()} | {:error, :unavailable}
  @callback complete(
              pos_integer(),
              binary(),
              [MovieCandidate.t()],
              MovieDetails.t() | nil,
              boolean()
            ) ::
              :ok | {:ok, :stale} | {:error, atom()}
  @callback fail(pos_integer(), binary(), atom()) ::
              :ok | {:ok, :stale} | {:error, atom()}
  @callback correct(pos_integer(), :unidentified | MovieDetails.t()) ::
              {:ok, Identification.t()} | {:error, atom()}
  @callback retry(pos_integer()) :: {:ok, Identification.t()} | {:error, atom()}
end
