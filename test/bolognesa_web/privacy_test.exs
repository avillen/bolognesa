defmodule BolognesaWeb.PrivacyTest do
  alias Phoenix.Logger, as: PhoenixLogger
  use ExUnit.Case, async: true

  test "Phoenix filters catalog and TMDb searches from request logs" do
    params = %{
      "search" => %{"query" => "My private movie"},
      "correction" => %{"query" => "Another private movie"},
      "token" => "secret"
    }

    filtered = PhoenixLogger.filter_values(params)

    assert filtered["search"]["query"] == "[FILTERED]"
    assert filtered["correction"]["query"] == "[FILTERED]"
    assert filtered["token"] == "[FILTERED]"
  end
end
