defmodule Bolognesa.MovieIdentificationFixtures do
  @moduledoc false
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Repo

  @spec insert_decision!(map(), pos_integer() | nil) :: MovieIdentificationSchema.t()
  def insert_decision!(attrs, movie_id) do
    Repo.insert!(
      MovieIdentificationSchema.changeset(
        %MovieIdentificationSchema{},
        Map.put(attrs, :movie_id, movie_id)
      )
    )
  end
end
