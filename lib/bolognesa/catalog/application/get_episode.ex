defmodule Bolognesa.Catalog.Application.GetEpisode do
  @moduledoc "Authorize an episode detail and physical versions."
  alias Bolognesa.Catalog.Application.Dto.EpisodeDetail
  alias Bolognesa.Catalog.Application.Ports.SeriesReader
  alias Bolognesa.Catalog.Domain.Episode
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor

  @spec call(Actor.t(), Episode.id(), SeriesReader.adapter()) ::
          {:ok, EpisodeDetail.t()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, id, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- valid_id(id),
         {:ok, result} <- reader.get_episode(id) do
      {:ok, EpisodeDetail.from_domain(result)}
    end
  end

  defp valid_id(id) when is_integer(id) and id > 0, do: :ok
  defp valid_id(_), do: {:error, :not_found}
end
