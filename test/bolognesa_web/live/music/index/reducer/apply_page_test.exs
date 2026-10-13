defmodule BolognesaWeb.Music.Index.Reducer.ApplyPageTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Music.Application.Dto.TrackPage
  alias BolognesaWeb.Music.Index.Reducer.ApplyPage

  test "stale success and stale errors cannot replace a newer request" do
    current = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, request_id: current, total: 99, loading?: true, error: nil}
    }

    assert socket == ApplyPage.call(socket, make_ref(), {:ok, {:ok, %TrackPage{total: 0}}})
    assert socket == ApplyPage.call(socket, make_ref(), {:ok, {:error, :unavailable}})
    failed = ApplyPage.call(socket, current, {:ok, {:error, :unavailable}})
    assert failed.assigns.total == 99
    assert failed.assigns.loading? == false
    assert is_binary(failed.assigns.error)
  end
end
