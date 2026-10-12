defmodule Bolognesa.Infrastructure.Services.PubSubNotificationsTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Infrastructure.Services.PubSubNotifications

  setup do
    start_supervised!({Phoenix.PubSub, name: :SharedNotificationsTestPubSub})
    %{opts: [pubsub: :SharedNotificationsTestPubSub]}
  end

  test "contexts can publish their own messages on separate topics", %{opts: opts} do
    assert :ok = PubSubNotifications.subscribe("libraries:statuses", opts)

    assert :ok =
             PubSubNotifications.broadcast(
               "playback:statuses",
               {:playback_changed, "session"},
               opts
             )

    refute_receive {:playback_changed, _}

    assert :ok = PubSubNotifications.subscribe("playback:statuses", opts)

    assert :ok =
             PubSubNotifications.broadcast(
               "playback:statuses",
               {:playback_changed, "session"},
               opts
             )

    assert_receive {:playback_changed, "session"}

    assert :ok =
             PubSubNotifications.broadcast(
               "libraries:statuses",
               {:library_status_changed, 17},
               opts
             )

    assert_receive {:library_status_changed, 17}
  end

  test "unavailable transport returns a bounded error to the calling context" do
    opts = [pubsub: :UnavailableSharedNotificationsPubSub]
    assert {:error, :unavailable} = PubSubNotifications.subscribe("example:statuses", opts)

    assert {:error, :unavailable} =
             PubSubNotifications.broadcast("example:statuses", {:status_changed, 17}, opts)
  end
end
