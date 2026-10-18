defmodule Bolognesa.Series.Application.UseCases.FetchNextEpisode do
  @moduledoc "Authorize ordered continuation after a completed episode file."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Domain.ReadModels.Episode

  @spec call(AuthenticatedUser.t(), Episode.id(), pos_integer(), SeriesReader.adapter()) ::
          {:ok, Episode.t()} | :not_found | {:error, :forbidden | :unavailable}
  def call(actor, episode_id, file_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin) do
      reader.fetch_next_episode(episode_id, file_id)
    end
  end
end
