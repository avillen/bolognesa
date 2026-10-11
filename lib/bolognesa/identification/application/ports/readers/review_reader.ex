defmodule Bolognesa.Identification.Application.Ports.Readers.ReviewReader do
  @moduledoc "Read domain records needed to assemble an identification review page."

  alias Bolognesa.Identification.Domain.Entities.Identification
  alias Bolognesa.Identification.Domain.ReadModels.{ReviewFile, ReviewMovie}

  @type adapter :: atom()
  @type entry :: {Identification.t(), ReviewFile.t(), ReviewMovie.t() | nil}
  @type result :: {[entry()], non_neg_integer()}

  @callback list_review_items(pos_integer()) :: {:ok, result()} | {:error, :unavailable}
end
