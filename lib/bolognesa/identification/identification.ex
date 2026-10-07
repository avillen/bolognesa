defmodule Bolognesa.Identification do
  @moduledoc "Public identification and manual correction API."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identification.Application.CorrectIdentification
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository
  alias Bolognesa.Identification.Infrastructure.TmdbMovieProvider

  @spec correct(Actor.t() | nil, pos_integer(), :unidentified | {:tmdb, pos_integer()}) ::
          {:ok, map()} | {:error, atom()}
  def correct(actor, file_id, choice),
    do:
      CorrectIdentification.call(
        actor,
        file_id,
        choice,
        EctoIdentificationRepository,
        TmdbMovieProvider
      )

  @spec retry(Actor.t() | nil, pos_integer()) :: {:ok, map()} | {:error, atom()}
  def retry(actor, file_id) do
    with :ok <- Identity.authorize(actor, :admin) do
      EctoIdentificationRepository.retry(file_id)
    end
  end

  @spec search_candidates(Actor.t() | nil, binary()) :: {:ok, list()} | {:error, atom()}
  def search_candidates(actor, query) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- valid_query(query) do
      TmdbMovieProvider.search(String.trim(query), nil)
    end
  end

  defp valid_query(query) when is_binary(query) do
    if String.valid?(query) and String.trim(query) != "" and byte_size(query) <= 256,
      do: :ok,
      else: {:error, :invalid_query}
  end

  defp valid_query(_query), do: {:error, :invalid_query}
end
