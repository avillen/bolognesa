defmodule Bolognesa.Libraries.LibraryStatusNotificationsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  test "only administrators may subscribe to status updates" do
    assert {:error, :forbidden} = Libraries.subscribe_status_updates(nil)

    assert {:error, :forbidden} =
             Libraries.subscribe_status_updates(%AuthenticatedUser{role: :member})

    assert :ok = Libraries.subscribe_status_updates(%AuthenticatedUser{role: :admin})
    assert :ok = LibraryStatusNotifications.notify(17)
    assert_receive {:library_status_changed, 17}
  end

  test "hints contain only a library reference and reach isolated subscribers" do
    start_supervised!({Phoenix.PubSub, name: :LibraryStatusTestPubSub})
    assert :ok = LibraryStatusNotifications.subscribe(pubsub: :LibraryStatusTestPubSub)
    assert :ok = LibraryStatusNotifications.notify(23, pubsub: :LibraryStatusTestPubSub)
    assert_receive {:library_status_changed, 23}
    refute_receive _
  end

  test "unavailable notification delivery stays best effort" do
    assert {:error, :unavailable} =
             LibraryStatusNotifications.subscribe(pubsub: :UnavailableLibraryStatusPubSub)

    log =
      capture_log(fn ->
        assert :ok =
                 LibraryStatusNotifications.notify(17, pubsub: :UnavailableLibraryStatusPubSub)
      end)

    assert log =~ "resource=notification outcome=degraded"
    refute log =~ "ArgumentError"
  end
end
