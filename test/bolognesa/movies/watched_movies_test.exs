defmodule Bolognesa.Movies.WatchedMoviesTest do
  use Bolognesa.DataCase, async: true
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Infrastructure.Persistence.MovieWatchedSchema
  alias Bolognesa.Infrastructure.Persistence.UserSchema
  alias Bolognesa.MovieIdentificationFixtures
  alias Bolognesa.Movies
  alias Bolognesa.Movies.Application.UseCases.RecordWatchedMovie
  alias Bolognesa.Movies.Infrastructure.Readers.EctoWatchedMoviesReader, as: Reader
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoWatchedMoviesRepository, as: Repository
  alias Bolognesa.SeriesFixtures
  alias Ecto.Changeset
  alias Ecto.UUID

  defmodule FailingRepository do
    @behaviour Bolognesa.Movies.Application.Ports.Repositories.WatchedMoviesRepository
    @impl true
    def upsert(_, _, _), do: {:error, :unavailable}
    @impl true
    def delete(_, _), do: {:error, :unavailable}
  end

  setup do
    actor = actor("viewer@example.com", "admin")
    library = SeriesFixtures.library(:movie)
    movie = movie(1)
    file = SeriesFixtures.file(library.id, "movie.mkv")
    identify(file, movie)
    %{actor: actor, library: library, movie: movie, media_file: file}
  end

  test "authorizes and records one row per account and movie", ctx do
    assert {:error, :forbidden} = Movies.record_watched(nil, ctx.movie.id, ctx.media_file.id)
    assert {:ok, %{last_watched_at: nil}} = Movies.get_movie(ctx.actor, ctx.movie.id)

    assert :ok = Movies.record_watched(ctx.actor, ctx.movie.id, ctx.media_file.id)
    assert {:ok, %{last_watched_at: first}} = Movies.get_movie(ctx.actor, ctx.movie.id)
    assert :ok = Movies.record_watched(ctx.actor, ctx.movie.id, ctx.media_file.id)
    assert {:ok, %{last_watched_at: second}} = Movies.get_movie(ctx.actor, ctx.movie.id)

    assert DateTime.compare(second, first) != :lt
    assert Repo.aggregate(MovieWatchedSchema, :count) == 1

    other = actor("other@example.com")
    assert {:ok, %{last_watched_at: nil}} = Movies.get_movie(other, ctx.movie.id)
  end

  test "marks a known movie now and unmarks it per account", ctx do
    assert {:error, :forbidden} = Movies.mark_watched(nil, ctx.movie.id)
    assert {:error, :forbidden} = Movies.unmark_watched(nil, ctx.movie.id)
    assert {:error, :not_found} = Movies.mark_watched(ctx.actor, 99_999_999)

    other = actor("other@example.com")
    assert :ok = Movies.mark_watched(ctx.actor, ctx.movie.id)
    assert :ok = Movies.mark_watched(other, ctx.movie.id)
    assert {:ok, %{last_watched_at: %DateTime{}}} = Movies.get_movie(ctx.actor, ctx.movie.id)

    assert :ok = Movies.unmark_watched(ctx.actor, ctx.movie.id)
    assert :ok = Movies.unmark_watched(ctx.actor, ctx.movie.id)
    assert {:ok, %{last_watched_at: nil}} = Movies.get_movie(ctx.actor, ctx.movie.id)
    assert {:ok, %{last_watched_at: %DateTime{}}} = Movies.get_movie(other, ctx.movie.id)
  end

  test "the upsert retains the greatest timestamp", ctx do
    later = ~U[2026-01-02 00:00:00.000000Z]
    assert :ok = Repository.upsert(ctx.actor.id, ctx.movie.id, later)
    assert :ok = Repository.upsert(ctx.actor.id, ctx.movie.id, ~U[2026-01-01 00:00:00.000000Z])
    assert {:ok, ^later} = Reader.fetch_last_watched_at(ctx.actor.id, ctx.movie.id)
  end

  test "unavailable or unrelated files record nothing", ctx do
    other_movie = movie(2)
    unrelated = SeriesFixtures.file(ctx.library.id, "other.mkv")
    identify(unrelated, other_movie)

    assert {:error, :not_found} = Movies.record_watched(ctx.actor, ctx.movie.id, unrelated.id)
    assert {:error, :not_found} = Movies.record_watched(ctx.actor, ctx.movie.id, 99_999_999)

    Repo.update!(Changeset.change(ctx.media_file, availability: :missing))

    assert {:error, :not_found} =
             Movies.record_watched(ctx.actor, ctx.movie.id, ctx.media_file.id)

    assert Repo.all(MovieWatchedSchema) == []
  end

  test "failed persistence emits a sanitized Movies observation", ctx do
    reference = make_ref()
    owner = self()
    event = [:bolognesa, :movies, :watched, :failed]

    :ok =
      :telemetry.attach(
        reference,
        event,
        fn name, measurements, metadata, _ -> send(owner, {name, measurements, metadata}) end,
        nil
      )

    on_exit(fn -> :telemetry.detach(reference) end)

    assert {:error, :unavailable} =
             RecordWatchedMovie.call(
               ctx.actor,
               ctx.movie.id,
               ctx.media_file.id,
               Reader,
               FailingRepository
             )

    assert_receive {^event, %{count: 1}, metadata}
    assert metadata == %{user_id: ctx.actor.id, file_id: ctx.media_file.id, reason: :unavailable}
  end

  test "state survives a version replacement and cascades with account or movie", ctx do
    assert :ok = Movies.record_watched(ctx.actor, ctx.movie.id, ctx.media_file.id)
    Repo.delete!(ctx.media_file)
    assert {:ok, %DateTime{}} = Reader.fetch_last_watched_at(ctx.actor.id, ctx.movie.id)

    Repo.delete!(Repo.get!(UserSchema, ctx.actor.id))
    assert Repo.all(MovieWatchedSchema) == []

    other = actor("cascade@example.com")
    assert :ok = Repository.upsert(other.id, ctx.movie.id, DateTime.utc_now())
    Repo.delete!(Repo.get!(MovieSchema, ctx.movie.id))
    assert Repo.all(MovieWatchedSchema) == []
  end

  defp actor(email, role \\ "member") do
    user =
      Repo.insert!(%UserSchema{name: "Viewer", email: email, hashed_password: "hash", role: role})

    %AuthenticatedUser{id: user.id, role: :admin}
  end

  defp movie(provider_id) do
    Repo.insert!(
      MovieSchema.changeset(%MovieSchema{}, %{
        provider: :tmdb,
        provider_id: provider_id,
        title: "Movie #{provider_id}"
      })
    )
  end

  defp identify(file, movie) do
    MovieIdentificationFixtures.insert_decision!(
      %{
        media_file_id: file.id,
        observed_revision: 1,
        token: UUID.generate(),
        state: :automatic,
        origin: :automatic
      },
      movie.id
    )
  end
end
