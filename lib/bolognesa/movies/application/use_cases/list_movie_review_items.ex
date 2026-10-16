defmodule Bolognesa.Movies.Application.UseCases.ListMovieReviewItems do
  @moduledoc "Authorize paginated identification review."

  alias Bolognesa.Accounts
  alias Bolognesa.Movies.Application.Ports.Readers.MovieReviewReader
  alias Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Item, as: MovieReviewItem
  alias Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Response, as: MovieReviewPage

  @spec call(
          Bolognesa.Accounts.Domain.Entities.Actor.t(),
          pos_integer(),
          MovieReviewReader.adapter()
        ) ::
          {:ok, MovieReviewPage.t()} | {:error, :forbidden | :invalid_page | :unavailable}
  def call(actor, page, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- validate_page(page),
         {:ok, {entries, total}} <- reader.list_review_items(page) do
      {:ok,
       %MovieReviewPage{items: Enum.map(entries, &MovieReviewItem.from_domain/1), total: total}}
    end
  end

  defp validate_page(page) when is_integer(page) and page > 0 and page <= 100_000, do: :ok
  defp validate_page(_page), do: {:error, :invalid_page}
end
