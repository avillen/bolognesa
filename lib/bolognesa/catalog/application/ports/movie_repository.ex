defmodule Bolognesa.Catalog.Application.Ports.MovieRepository do
  @moduledoc "Catalog writer used inside an existing database transaction."
  alias Bolognesa.Catalog.Domain.{Movie, NewMovie}

  @callback upsert!(module(), NewMovie.t()) :: Movie.t()
end
