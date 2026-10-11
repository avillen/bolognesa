defmodule Bolognesa.SeriesFixtures do
  @moduledoc false
  alias Bolognesa.Identification.Application.CorrectSeriesIdentification
  alias Bolognesa.Identification.Domain.Identification
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Infrastructure.Persistence.{LibrarySchema, MediaFileSchema}
  alias Bolognesa.Repo
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
