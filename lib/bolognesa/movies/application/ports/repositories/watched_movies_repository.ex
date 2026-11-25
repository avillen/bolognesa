defmodule Bolognesa.Movies.Application.Ports.Repositories.WatchedMoviesRepository do
  @moduledoc "Atomic account-scoped watched writes; no inventory references."
  alias Bolognesa.Movies.Domain.ReadModels.Movie

  @type adapter :: module()

  @doc "Atomically upsert the movie's watched row, retaining the greatest timestamp."
  @callback upsert(user_id :: pos_integer(), Movie.id(), DateTime.t()) ::
              :ok | {:error, :unavailable}

  @doc "Delete the movie's watched row for the account. A missing row is a no-op."
  @callback delete(user_id :: pos_integer(), Movie.id()) :: :ok | {:error, :unavailable}
end
