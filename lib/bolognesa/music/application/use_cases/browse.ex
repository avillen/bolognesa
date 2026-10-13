defmodule Bolognesa.Music.Application.UseCases.Browse do
  @moduledoc "Authorized, bounded browsing of existing local identities."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Music.Application.Dto.BrowsePage
  alias Bolognesa.Music.Application.Ports.Readers.BrowseReader

  @type result ::
          {:ok, BrowsePage.t()}
          | {:error, :forbidden | :invalid_query | :not_found | :unavailable}
  @spec call(
          Actor.t() | nil,
          BrowseReader.kind(),
          pos_integer() | nil,
          String.t(),
          pos_integer(),
          pos_integer() | nil,
          BrowseReader.adapter()
        ) :: result()
  def call(actor, kind, artist_id, query, page, library_id, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         true <-
           kind in [:artists, :albums] and valid_id?(artist_id) and valid_id?(library_id) and
             is_binary(query) and String.valid?(query) and byte_size(query) <= 256 and
             is_integer(page) and page in 1..100_000,
         {:ok, result} <- reader.browse(kind, artist_id, query, page, library_id) do
      {:ok, BrowsePage.from_domain(result)}
    else
      false -> {:error, :invalid_query}
      error -> error
    end
  end

  defp valid_id?(nil), do: true
  defp valid_id?(id), do: is_integer(id) and id > 0
end
