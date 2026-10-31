defmodule BolognesaWeb.Episode.Show.ReducersTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias BolognesaWeb.Episode.Show.Live
  alias BolognesaWeb.Episode.Show.Reducer.Advance
  alias BolognesaWeb.Episode.Show.Reducer.ApplyResult
  alias BolognesaWeb.Episode.Show.Reducer.SelectPart

  test "selecting another part discards an outstanding continuation" do
    request = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        advance_request: request,
        transcode_session: nil,
        detail: %{
          versions: [%{id: 2, part_number: 2, availability: :missing}],
          episode: %{id: 1},
          season: %{id: 1},
          previous_entry: nil,
          next_entry: nil
        }
      }
    }

    selected = SelectPart.call(socket, 2)
    assert selected.assigns.advance_request == nil
    assert Advance.apply_result(selected, request, {:ok, {:ok, %Episode{id: 123}}}) == selected
  end

  test "completion during navigation cannot replace the requested episode" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        loading?: true,
        advance_request: nil,
        transcode_session: nil,
        selected_file_id: 1,
        playback_error: nil
      }
    }

    assert Advance.call(socket, %{"file_id" => "1"}) == socket
  end

  test "duplicate HLS completion cannot start another continuation" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        advance_request: make_ref(),
        transcode_session: %{id: "active"}
      }
    }

    assert Advance.call(socket, %{"session_id" => "active"}) == socket
    assert Advance.call(socket, %{"session_id" => "expired"}) == socket
  end

  test "stale playback actions preserve a pending continuation" do
    request = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, advance_request: request, transcode_session: nil}
    }

    {:noreply, restarted} =
      Live.handle_event(
        "playback_seek",
        %{"session_id" => "expired", "position_ms" => "0"},
        socket
      )

    result = {:ok, {:ok, %Episode{id: 123}}}

    assert restarted == socket
    assert Advance.apply_result(restarted, request, result).redirected != nil
  end

  test "an accepted restart discards a pending continuation even when preparation fails" do
    request = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        advance_request: request,
        current_scope: %{actor: nil},
        content_ref: {:episode, 1},
        transcode_session: %{
          id: "current",
          duration_ms: nil,
          strategy: :full_transcode,
          file_id: 1
        }
      }
    }

    {:noreply, restarted} =
      Live.handle_event(
        "playback_seek",
        %{"session_id" => "current", "position_ms" => "0"},
        socket
      )

    result = {:ok, {:ok, %Episode{id: 123}}}
    assert Advance.apply_result(restarted, request, result) == restarted
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
        transcode_session: nil
      }
    }

    result = {:ok, {:error, :too_many_versions}}
    updated = ApplyResult.call(socket, request, result)
    assert updated.assigns.loading? == false
    assert updated.assigns.error =~ "100"
    assert updated.assigns.detail == nil
    assert updated.assigns.selected_file_id == nil
    assert ApplyResult.call(socket, make_ref(), result) == socket
  end
end
