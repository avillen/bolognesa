defmodule BolognesaWeb.Episode.Show.ReducersTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias BolognesaWeb.Episode.Show.Live
  alias BolognesaWeb.Episode.Show.Reducer.Advance
  alias BolognesaWeb.Episode.Show.Reducer.ApplyResult

  test "stale playback actions preserve a pending continuation" do
    request = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, advance_request: request, compatible_session: nil}
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
        compatible_session: %{id: "current", duration_ms: nil, profile: :video, file_id: 1}
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
      assigns: %{__changed__: %{}, request_id: request, loading?: true, error: nil}
    }

    result = {:ok, {:error, :too_many_versions}}
    updated = ApplyResult.call(socket, request, result)
    assert updated.assigns.loading? == false
    assert updated.assigns.error =~ "100"
    assert ApplyResult.call(socket, make_ref(), result) == socket
  end
end
