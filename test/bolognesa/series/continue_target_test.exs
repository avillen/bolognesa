defmodule Bolognesa.Series.ContinueTargetTest do
  use Bolognesa.DataCase, async: true
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.UserSchema
  alias Bolognesa.Series
  alias Bolognesa.Series.Domain.ValueObjects.Entry
  alias Bolognesa.Series.Infrastructure.Repositories.EctoWatchedEntriesRepository, as: Repository
  alias Bolognesa.SeriesFixtures
  alias Ecto.Changeset

  setup do
    users =
      for {name, role} <- [{"viewer", "admin"}, {"other", "member"}],
          do:
            Repo.insert!(%UserSchema{
              name: name,
              email: "#{name}@example.com",
              hashed_password: "hash",
              role: role
            })

    library = SeriesFixtures.library()
    special = SeriesFixtures.file(library.id, "Example S00E01.mp4")
    [special_id] = SeriesFixtures.identify(special, 0, [1]).episode_ids

    [first_id, second_id, third_id] =
      for {season, number} <- [{1, 1}, {1, 2}, {2, 1}] do
        file = SeriesFixtures.file(library.id, "Example S0#{season}E0#{number}.mp4")
        [id] = SeriesFixtures.identify(file, season, [number]).episode_ids

        if {season, number} == {1, 2},
          do: Repo.update!(Changeset.change(file, availability: :missing))

        id
      end

    {:ok, detail} = Series.fetch_episode(admin(hd(users)), first_id)

    %{
      actor: admin(hd(users)),
      other: List.last(users),
      series_id: detail.series.id,
      library: library,
      ids: %{special: special_id, first: first_id, second: second_id, third: third_id}
    }
  end

  defp admin(user), do: %AuthenticatedUser{id: user.id, role: :admin}

  defp watch(user, episode_id, part \\ nil, at \\ DateTime.utc_now()),
    do:
      :ok =
        Repository.upsert(user.id, [%Entry{episode_id: episode_id, part_number: part}], at)

  defp target(ctx) do
    {:ok, %{action: action, entry: entry}} =
      Series.fetch_continue_target(ctx.actor, ctx.series_id)

    {action, entry.season_number, entry.number}
  end

  test "starts at the first regular entry even when only specials are watched", ctx do
    assert target(ctx) == {:start, 1, 1}
    watch(ctx.actor, ctx.ids.special)
    assert target(ctx) == {:start, 1, 1}
  end

  test "continues to a known unavailable entry and ignores other accounts", ctx do
    watch(ctx.other, ctx.ids.third)
    watch(ctx.actor, ctx.ids.first)
    assert target(ctx) == {:continue, 1, 2}
  end

  test "replays when the last available entry is watched", ctx do
    watch(ctx.actor, ctx.ids.third)
    assert target(ctx) == {:replay, 1, 1}
  end

  test "authorizes the caller", ctx do
    assert {:error, :forbidden} = Series.fetch_continue_target(nil, ctx.series_id)
    assert {:ok, nil} = Series.fetch_continue_target(ctx.actor, -1)
  end

  test "numbered parts are separate entries", ctx do
    one = SeriesFixtures.file(ctx.library.id, "Example S02E02-part1.mp4")
    two = SeriesFixtures.file(ctx.library.id, "Example S02E02-part2.mp4")
    [fourth] = SeriesFixtures.identify(one, 2, [2]).episode_ids
    SeriesFixtures.identify(two, 2, [2])
    watch(ctx.actor, ctx.ids.third)
    watch(ctx.actor, fourth, 1, DateTime.add(DateTime.utc_now(), 1))

    assert {:ok, %{action: :continue, entry: %{part_number: 2}}} =
             Series.fetch_continue_target(ctx.actor, ctx.series_id)
  end
end
