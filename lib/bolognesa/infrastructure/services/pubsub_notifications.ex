defmodule Bolognesa.Infrastructure.Services.PubSubNotifications do
  @moduledoc "Shared Phoenix.PubSub transport with bounded availability errors."

  alias Phoenix.PubSub

  @type options :: [pubsub: PubSub.t()]
  @type result :: :ok | {:error, :unavailable}

  @spec subscribe(PubSub.topic(), options()) :: result()
  def subscribe(topic, opts \\ []) do
    case PubSub.subscribe(pubsub(opts), topic) do
      :ok -> :ok
      {:error, _reason} -> {:error, :unavailable}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec broadcast(PubSub.topic(), PubSub.message(), options()) :: result()
  def broadcast(topic, message, opts \\ []) do
    case PubSub.broadcast(pubsub(opts), topic, message) do
      :ok -> :ok
      {:error, _reason} -> {:error, :unavailable}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp pubsub(opts), do: Keyword.get(opts, :pubsub, Bolognesa.PubSub)
end
