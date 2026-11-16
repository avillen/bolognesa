defmodule BolognesaWeb.Series.Review.ReducersTest do
  alias Phoenix.Component
  use ExUnit.Case, async: true
  alias BolognesaWeb.Series.Review.Forms.Selection

  alias BolognesaWeb.Series.Review.Reducer.ApplyCandidatesResult
  alias BolognesaWeb.Series.Review.Reducer.ApplyCorrectionResultCoordinator
  alias BolognesaWeb.Series.Review.Reducer.ApplySeasonResult
  alias BolognesaWeb.Series.Review.Reducer.BeginCorrectionCoordinator
  alias BolognesaWeb.Series.Review.Reducer.ChooseSeriesCoordinator
  alias BolognesaWeb.Series.Review.Reducer.Initialize
  alias BolognesaWeb.Series.Review.Reducer.LoadSeason
  alias BolognesaWeb.Series.Review.Reducer.Save
  alias BolognesaWeb.Series.Review.Reducer.Search

  test "empty episode selections are invalid before calling the provider" do
    changeset = Selection.changeset(%{"episode_numbers" => [""]})
    assert changeset.valid? == false, inspect(changeset)
  end

  test "a late search or season result cannot overwrite the new selection" do
    socket =
      Initialize.call(%Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}},
        private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
      })

    old = make_ref()
    newer = make_ref()

    socket =
      Component.assign(socket,
        requests: %{candidates: newer, season: newer},
        series_id: 202
      )

    assert ApplyCandidatesResult.call(socket, old, {:ok, {:ok, []}}) == socket
    assert ApplySeasonResult.call(socket, old, {:ok, {:error, :unavailable}}) == socket
  end

  test "finished requests are consumed and cannot replace validation feedback" do
    socket =
      Initialize.call(%Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}},
        private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
      })

    ref = make_ref()
    socket = Component.assign(socket, requests: %{correction: ref}, saving?: true)

    completed =
      ApplyCorrectionResultCoordinator.call(socket, ref, {:ok, {:error, :source_changed}})

    assert completed.assigns.saving? == false
    assert completed.assigns.requests == %{}
    assert ApplyCorrectionResultCoordinator.call(completed, ref, {:exit, :cancelled}) == completed
  end

  test "a second submit and changes of selection are ignored while saving" do
    socket =
      Initialize.call(%Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}},
        private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
      })

    socket = Component.assign(socket, saving?: true)
    assert BeginCorrectionCoordinator.call(socket, %{"episode_numbers" => ["2"]}) == socket
    assert Save.call(socket, :unidentified) == socket
    assert Search.call(socket, "Another") == socket
    assert ChooseSeriesCoordinator.call(socket, 202) == socket
    assert LoadSeason.call(socket, 2) == socket
  end
end
