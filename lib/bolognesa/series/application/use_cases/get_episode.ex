defmodule Bolognesa.Series.Application.UseCases.GetEpisode do
  @moduledoc "Authorize an episode detail and physical versions."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Application.UseCases.GetEpisode.Response, as: EpisodeDetail
  alias Bolognesa.Series.Domain.ReadModels.Episode

  @spec call(AuthenticatedUser.t(), Episode.id(), SeriesReader.adapter()) ::
          {:ok, EpisodeDetail.t()}
          | {:error, :forbidden | :not_found | :unavailable | :too_many_versions}
  def call(actor, id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- valid_id(id),
         {:ok, result} <- reader.get_episode(id) do
      {:ok, EpisodeDetail.from_domain(result)}
    end
  end

  defp valid_id(id) when is_integer(id) and id > 0, do: :ok
  defp valid_id(_), do: {:error, :not_found}
end
