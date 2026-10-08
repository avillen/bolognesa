defmodule Bolognesa.Catalog.Application.Ports.MovieRepository do
  @moduledoc "Catalog writer used inside an existing database transaction."

  @callback upsert!(module(), map()) :: %{id: pos_integer()}
end
