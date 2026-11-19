defmodule Bolognesa.Movies.Application.UseCases.ListMovieReviewItems do
  @moduledoc "Authorize paginated identification review."

  alias Bolognesa.Accounts
  alias Bolognesa.Movies.Application.Ports.Readers.MovieReviewReader
  alias Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Item, as: MovieReviewItem
  alias Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Response, as: MovieReviewPage
  alias Bolognesa.ReadQuery

  @spec call(
          Bolognesa.Accounts.Domain.Entities.AuthenticatedUser.t(),
          pos_integer(),
          MovieReviewReader.adapter()
        ) ::
          {:ok, MovieReviewPage.t()} | {:error, :forbidden | :invalid_page | :unavailable}
  def call(actor, page, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <- ReadQuery.valid_page?(page) || {:error, :invalid_page},
         {:ok, {entries, total}} <- reader.list_review_items(page) do
      {:ok,
       %MovieReviewPage{items: Enum.map(entries, &MovieReviewItem.from_domain/1), total: total}}
    end
  end
end
