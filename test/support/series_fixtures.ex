defmodule Bolognesa.SeriesFixtures do
  @moduledoc false
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Repo
  alias Bolognesa.Series.Application.UseCases.CorrectSeriesIdentification
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository
  alias Bolognesa.Test.SyntheticSeriesProvider

  @spec library(:movie | :series) :: LibrarySchema.t()
  def library(type \\ :series),
    do:
      Repo.insert!(%LibrarySchema{
        name: "Synthetic source",
        path: "/synthetic/#{Ecto.UUID.generate()}",
        content_type: type
      })

  @spec file(pos_integer(), binary()) :: MediaFileSchema.t()
  def file(library_id, name),
    do:
      Repo.insert!(%MediaFileSchema{
        library_id: library_id,
        relative_path: name,
        size_bytes: 8,
        modified_at: DateTime.utc_now(),
        availability: :available,
        revision: 1,
        last_seen_generation: Ecto.UUID.generate()
      })

  @spec identify(MediaFileSchema.t(), non_neg_integer(), [pos_integer()]) :: Identification.t()
  def identify(file, season, numbers) do
    {:ok, decision} =
      CorrectSeriesIdentification.call(
        %Actor{id: 1, role: :admin},
        file.id,
        {:tmdb, 201, season, numbers},
        EctoIdentificationRepository,
        SyntheticSeriesProvider
      )

    decision
  end
end
