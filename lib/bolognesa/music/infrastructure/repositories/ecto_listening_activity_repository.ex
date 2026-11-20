defmodule Bolognesa.Music.Infrastructure.Repositories.EctoListeningActivityRepository do
  @moduledoc false
  @behaviour Bolognesa.Music.Application.Ports.Repositories.ListeningActivityRepository
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.MusicListeningActivitySchema
  alias Bolognesa.Repo

  @impl true
  def record(user_id, track_id) do
    on_conflict =
      from activity in MusicListeningActivitySchema,
        update: [
          set: [
            last_played_at:
              fragment("GREATEST(?, EXCLUDED.last_played_at)", activity.last_played_at)
          ]
        ]

    Repo.insert_all(
      MusicListeningActivitySchema,
      [%{user_id: user_id, track_id: track_id, last_played_at: DateTime.utc_now()}],
      on_conflict: on_conflict,
      conflict_target: [:user_id, :track_id],
      log: false
    )

    :ok
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end
