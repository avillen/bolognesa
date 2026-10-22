defmodule Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications do
  @moduledoc "Best-effort hints for authorized clients to re-read persisted library status."
  @behaviour Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier

  alias Bolognesa.Infrastructure.Observability.Events

  alias Bolognesa.Infrastructure.Services.PubSubNotifications
  alias Bolognesa.Libraries.Domain.Entities.Library

  @topic "libraries:statuses"
  @type options :: PubSubNotifications.options()

  @spec subscribe(options()) :: :ok | {:error, :unavailable}
  def subscribe(opts \\ []), do: PubSubNotifications.subscribe(@topic, opts)

  @impl true
  def notify(library_id), do: notify(library_id, [])

  @spec notify(Library.id(), options()) :: :ok
  def notify(library_id, opts) do
    case PubSubNotifications.broadcast(@topic, {:library_status_changed, library_id}, opts) do
      :ok -> :ok
      {:error, _reason} -> unavailable(library_id)
    end
  end

  defp unavailable(library_id) do
    Events.emit(:libraries, :notification, :degraded, %{
      library_id: library_id,
      reason: :notification_unavailable
    })

    :ok
  end
end
