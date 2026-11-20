defmodule Bolognesa.Series.RecentSeriesTest do
  use Bolognesa.DataCase, async: true
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.UserSchema
  alias Bolognesa.Series
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry
  alias Bolognesa.Series.Infrastructure.Repositories.EctoWatchedEntriesRepository, as: Repository
  alias Bolognesa.SeriesFixtures

  setup do
    [viewer, other] =
      for {name, role} <- [{"viewer", "admin"}, {"other", "member"}],
          do:
            Repo.insert!(%UserSchema{
              name: name,
              email: "#{name}@example.com",
              hashed_password: "hash",
              role: role
            })

    %{
      actor: %AuthenticatedUser{id: viewer.id, role: :admin},
      other: other,
      library: SeriesFixtures.library()
    }
  end

  defp episodes(library, provider_id) do
    for number <- [1, 2] do
      file = SeriesFixtures.file(library.id, "Series #{provider_id} E0#{number}.mp4")
      hd(SeriesFixtures.identify(file, 1, [number], provider_id).episode_ids)
    end
  end

  defp watch(user_id, episode_id, days_ago),
    do:
      :ok =
        Repository.upsert(
          user_id,
          [%SeasonEntry{episode_id: episode_id, part_number: nil}],
          DateTime.add(DateTime.utc_now(), -days_ago * 86_400)
        )

  defp series_id(actor, episode_id) do
    {:ok, %{series: series}} = Series.fetch_episode(actor, episode_id)
    series.id
  end

  defp recent(ctx, library_id \\ nil) do
    {:ok, recent} = Series.list_recent_series(ctx.actor, library_id)
    for {series, target} <- recent, do: {series.id, target.action, target.entry.number}
  end

  test "lists the three most recently watched series, newest first, with their targets", ctx do
    [first, second, third, fourth] =
      for {provider_id, days_ago} <- [{201, 4}, {202, 3}, {203, 2}, {204, 1}] do
        [one, two] = episodes(ctx.library, provider_id)
        watch(ctx.actor.id, one, days_ago)
        if provider_id == 203, do: watch(ctx.actor.id, two, days_ago)
        one
      end

    ids = &series_id(ctx.actor, &1)

    assert recent(ctx) == [
             {ids.(fourth), :continue, 2},
             {ids.(third), :replay, 1},
             {ids.(second), :continue, 2}
           ]

    refute ids.(first) in Enum.map(recent(ctx), &elem(&1, 0))
  end

  test "ignores other accounts and returns nothing without watched state", ctx do
    [one, _] = episodes(ctx.library, 201)
    assert recent(ctx) == []
    watch(ctx.other.id, one, 0)
    assert recent(ctx) == []
  end

  test "selects series from the library before applying the limit", ctx do
    other_library = SeriesFixtures.library()

    watched =
      for {library, provider_id, days_ago} <- [
            {ctx.library, 201, 4},
            {other_library, 202, 3},
            {other_library, 203, 2},
            {other_library, 204, 1}
          ] do
        [one, _] = episodes(library, provider_id)
        watch(ctx.actor.id, one, days_ago)
        one
      end

    assert [{series_id(ctx.actor, hd(watched)), :continue, 2}] == recent(ctx, ctx.library.id)
    assert length(recent(ctx, other_library.id)) == 3
    assert length(recent(ctx)) == 3
  end

  test "authorizes the caller and validates the library", ctx do
    assert {:error, :forbidden} = Series.list_recent_series(nil, nil)
    assert {:error, :invalid_query} = Series.list_recent_series(ctx.actor, 0)
  end
end
