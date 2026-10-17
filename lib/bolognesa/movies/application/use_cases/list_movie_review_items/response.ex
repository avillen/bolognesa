defmodule Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Response do
  @moduledoc "A page of identification review items."

  alias Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Item, as: MovieReviewItem

  @type t :: %__MODULE__{
          items: [MovieReviewItem.t()],
          total: non_neg_integer()
        }

  defstruct [:items, :total]
end
