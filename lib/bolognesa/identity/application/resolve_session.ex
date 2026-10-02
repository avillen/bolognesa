defmodule Bolognesa.Identity.Application.ResolveSession do
  @moduledoc "Resolve a cookie token against an active database session."
  alias Bolognesa.Identity.Domain.Actor

  @spec call(term(), module()) :: {:ok, Actor.t()} | {:error, :unauthenticated | :unavailable}
  def call(token, repository) do
    with {:ok, raw} <- decode(token) do
      case repository.find_active_session(:crypto.hash(:sha256, raw), DateTime.utc_now()) do
        {:ok, user} -> {:ok, Actor.from_user(user)}
        :not_found -> {:error, :unauthenticated}
        {:error, :unavailable} = error -> error
      end
    end
  end

  @spec decode(term()) :: {:ok, binary()} | {:error, :unauthenticated}
  def decode(token) when is_binary(token) and byte_size(token) == 43 do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} when byte_size(raw) == 32 -> {:ok, raw}
      _ -> {:error, :unauthenticated}
    end
  end

  def decode(_), do: {:error, :unauthenticated}
end
