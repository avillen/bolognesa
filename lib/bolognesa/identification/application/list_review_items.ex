defmodule Bolognesa.Identification.Application.ListReviewItems do
  @moduledoc "Authorize paginated identification review."
  alias Bolognesa.Identity

  @spec call(Bolognesa.Identity.Domain.Actor.t(), pos_integer(), module()) ::
          {:ok, map()} | {:error, atom()}
  def call(actor, page, reader) do
    with :ok <- Identity.authorize(actor, :admin) do
      if is_integer(page) and page > 0 and page <= 100_000,
        do: reader.list_review_items(page),
        else: {:error, :invalid_page}
    end
  end
end
