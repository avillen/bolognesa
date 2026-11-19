defmodule Bolognesa.Infrastructure.Persistence.SeriesWatchedEntrySchema do
  @moduledoc false
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "series_watched_entries" do
    field :user_id, :id
    field :episode_id, :id
    field :part_number, :integer
    field :last_watched_at, :utc_datetime_usec
  end
end
