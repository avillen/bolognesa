defmodule Bolognesa.Identification.Application.Ports.ReviewReader do
  @moduledoc "Read domain records needed to assemble an identification review page."

  alias Bolognesa.Catalog.Domain.Movie
  alias Bolognesa.Identification.Domain.Identification
  alias Bolognesa.Libraries.Domain.MediaFile

  @type adapter :: atom()
  @type entry :: {Identification.t(), MediaFile.t(), Movie.t() | nil}
  @type result :: {[entry()], non_neg_integer()}

  @callback list_review_items(pos_integer()) :: {:ok, result()} | {:error, :unavailable}
end
