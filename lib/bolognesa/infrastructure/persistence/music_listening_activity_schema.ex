defmodule Bolognesa.Infrastructure.Persistence.MusicListeningActivitySchema do
  @moduledoc false
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "music_listening_activity" do
    field :user_id, :id
    field :track_id, :id
    field :last_played_at, :utc_datetime_usec
  end
end
