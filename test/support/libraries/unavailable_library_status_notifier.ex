defmodule Bolognesa.Libraries.Support.UnavailableLibraryStatusNotifier do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier

  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  @impl true
  def notify(library_id),
    do: LibraryStatusNotifications.notify(library_id, pubsub: :UnavailableLibraryStatusPubSub)
end
