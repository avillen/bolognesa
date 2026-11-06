defmodule Bolognesa.Music.Infrastructure.Repositories.EctoListeningActivityRepository do
  @moduledoc false
  @behaviour Bolognesa.Music.Application.Ports.Repositories.ListeningActivityRepository
  alias Bolognesa.Repo

  @impl true
  def record(user_id, track_id) do
    Repo.query!(
      """
      INSERT INTO music_listening_activity (user_id, track_id, last_played_at)
      VALUES ($1, $2, now())
      ON CONFLICT (user_id, track_id) DO UPDATE SET last_played_at = GREATEST(music_listening_activity.last_played_at, EXCLUDED.last_played_at)
      """,
      [user_id, track_id],
      log: false
    )

    :ok
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end
