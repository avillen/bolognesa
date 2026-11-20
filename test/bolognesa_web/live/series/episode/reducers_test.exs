defmodule BolognesaWeb.Series.Episode.ReducersTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Series.Domain.ReadModels.EntryStatus
  alias BolognesaWeb.LiveSupport.PlaybackAttempt
  alias BolognesaWeb.Series.Episode.Live
  alias BolognesaWeb.Series.Episode.Reducer.Advance
  alias BolognesaWeb.Series.Episode.Reducer.ApplyAdvanceResult
  alias BolognesaWeb.Series.Episode.Reducer.ApplyResultCoordinator
  alias BolognesaWeb.Series.Episode.Reducer.SelectPart

  test "selecting another part discards an outstanding continuation" do
    request = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        advance_request: request,
        playback: PlaybackAttempt.new(),
        detail: %{
          versions: [%{id: 2, part_number: 2, availability: :missing}],
          episode: %{id: 1},
          season: %{id: 1},
          entries: []
        }
      }
    }

    selected = SelectPart.call(socket, 2)
    assert selected.assigns.advance_request == nil

    assert ApplyAdvanceResult.call(
             selected,
             request,
             {:ok,
              {:ok,
               %EntryStatus{
                 episode_id: 123,
                 season_id: 1,
                 season_number: 1,
                 number: 1,
                 part_number: nil,
                 available?: true
               }}}
           ) == selected
  end

  test "completion during navigation cannot replace the requested episode" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        loading?: true,
        advance_request: nil,
        playback: %PlaybackAttempt{phase: :ready, file_id: 1}
      }
    }

    assert Advance.call(socket, %{"file_id" => "1"}) == socket
  end

  test "duplicate HLS completion cannot start another continuation" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        advance_request: make_ref(),
        playback: %PlaybackAttempt{session: %{id: "active"}}
      }
    }

    assert Advance.call(socket, %{"session_id" => "active"}) == socket
    assert Advance.call(socket, %{"session_id" => "expired"}) == socket
  end

  test "stale playback actions preserve a pending continuation" do
    request = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, advance_request: request, playback: PlaybackAttempt.new()}
    }

    {:noreply, restarted} =
      Live.handle_event(
        "playback_seek",
        %{"session_id" => "expired", "position_ms" => "0"},
        socket
      )

    result =
      {:ok,
       {:ok,
        %EntryStatus{
          episode_id: 123,
          season_id: 1,
          season_number: 1,
          number: 1,
          part_number: nil,
          available?: true
        }}}

    assert restarted == socket
    assert ApplyAdvanceResult.call(restarted, request, result).redirected != nil
  end

  test "an accepted restart discards a pending continuation even when preparation fails" do
    request = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        advance_request: request,
        current_scope: %{actor: nil},
        content_ref: {:episode, 1},
        playback: %PlaybackAttempt{
          phase: :ready,
          file_id: 1,
          session: %{id: "current", duration_ms: nil, file_id: 1}
        }
      }
    }

    {:noreply, restarted} =
      Live.handle_event(
        "playback_seek",
        %{"session_id" => "current", "position_ms" => "0"},
        socket
      )

    result =
      {:ok,
       {:ok,
        %EntryStatus{
          episode_id: 123,
          season_id: 1,
          season_number: 1,
          number: 1,
          part_number: nil,
          available?: true
        }}}

    assert ApplyAdvanceResult.call(restarted, request, result) == restarted
    assert restarted.redirected == nil
  end

  test "oversized details show an explicit limit and stale failures are ignored" do
    request = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        request_id: request,
        loading?: true,
        error: nil,
        detail: %{episode: %{id: 1}},
        playback: PlaybackAttempt.new()
      }
    }

    result = {:ok, {:error, :too_many_versions}}
    updated = ApplyResultCoordinator.call(socket, request, result)
    assert updated.assigns.loading? == false
    assert updated.assigns.error =~ "100"
    assert updated.assigns.detail == nil
    assert updated.assigns.playback == PlaybackAttempt.new()
    assert ApplyResultCoordinator.call(socket, make_ref(), result) == socket
  end
end
