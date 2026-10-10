defmodule Bolognesa.Catalog.Application.GetMovie do
  @moduledoc "Authorize a movie detail read."
  alias Bolognesa.Identity

  @spec call(Bolognesa.Identity.Domain.Actor.t(), pos_integer(), module()) ::
          {:ok, map()} | {:error, atom()}
  def call(actor, id, reader) do
    with :ok <- Identity.authorize(actor, :admin) do
      if is_integer(id) and id > 0, do: reader.get_movie(id), else: {:error, :not_found}
    end
  end
end
