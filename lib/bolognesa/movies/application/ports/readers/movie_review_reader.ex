defmodule Bolognesa.Movies.Application.Ports.Readers.MovieReviewReader do
  @moduledoc "Read domain records needed to assemble an identification review page."

  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Domain.ReadModels.ReviewMovie
  alias Bolognesa.Movies.Domain.ReadModels.ReviewMovieFile

  @type adapter :: atom()
  @type entry :: {Identification.t(), ReviewMovieFile.t(), ReviewMovie.t() | nil}
  @type result :: {[entry()], non_neg_integer()}

  @callback list_review_items(pos_integer()) :: {:ok, result()} | {:error, :unavailable}
end
