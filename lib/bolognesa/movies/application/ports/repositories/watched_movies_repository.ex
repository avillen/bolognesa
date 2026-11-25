defmodule Bolognesa.Movies.Application.Ports.Repositories.WatchedMoviesRepository do
  @moduledoc "Atomic account-scoped watched writes; no inventory references."
  alias Bolognesa.Movies.Domain.ReadModels.Movie

  @type adapter :: module()

  @doc "Atomically upsert the movie's watched row, retaining the greatest timestamp."
  @callback upsert(user_id :: pos_integer(), Movie.id(), DateTime.t()) ::
              :ok | {:error, :unavailable}
end
