defmodule Bolognesa.Infrastructure.Persistence.MovieWatchedSchema do
  @moduledoc false
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "movies_watched" do
    field :user_id, :id, primary_key: true
    field :movie_id, :id, primary_key: true
    field :last_watched_at, :utc_datetime_usec
  end
end
