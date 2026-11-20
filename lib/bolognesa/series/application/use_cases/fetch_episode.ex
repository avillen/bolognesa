defmodule Bolognesa.Series.Application.UseCases.FetchEpisode do
  @moduledoc "Authorize an episode detail and physical versions."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.ReadQuery
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Application.UseCases.FetchEpisode.Response, as: EpisodeDetail
  alias Bolognesa.Series.Domain.ReadModels.Episode

  @spec call(AuthenticatedUser.t(), Episode.id(), SeriesReader.adapter()) ::
          {:ok, EpisodeDetail.t()}
          | {:error, :forbidden | :not_found | :unavailable | :too_many_versions}
  def call(actor, id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate_id(id),
         {:ok, result} <- reader.fetch_episode(id) do
      {:ok, EpisodeDetail.from_domain(result)}
    end
  end
end
