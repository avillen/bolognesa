defmodule Bolognesa.Accounts.SessionLifetimeTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Accounts.Domain.Entities.Session

  test "sessions retain their issue time and expire after thirty days across calendar boundaries" do
    issued_at = ~U[2026-02-01 12:00:00.123456Z]
    session = Session.new(1, <<1, 2, 3>>, issued_at)

    assert session.issued_at == issued_at
    assert session.expires_at == ~U[2026-03-03 12:00:00.123456Z]
  end
end
