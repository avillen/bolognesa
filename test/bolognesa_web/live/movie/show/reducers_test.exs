defmodule BolognesaWeb.Movie.Show.ReducersTest do
  use ExUnit.Case, async: true
  alias BolognesaWeb.Movie.Show.Reducer.ApplyResult

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
