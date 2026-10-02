defmodule Bolognesa.Identity.Application.ResolveSession do
  @moduledoc "Resolve a cookie token against an active database session."
  alias Bolognesa.Identity.Application.Ports.Repository
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identity.Domain.Session

  @spec call(Session.token() | nil, Repository.adapter()) ::
          {:ok, Actor.t()} | {:error, :unauthenticated | :unavailable}
  def call(token, repository) do
    with {:ok, raw} <- decode(token),
         {:ok, user} <- find_active_user(raw, repository) do
      {:ok, Actor.from_user(user)}
    end
  end

  @spec decode(Session.token() | nil) :: {:ok, binary()} | {:error, :unauthenticated}
  def decode(token) when is_binary(token) and byte_size(token) == 43 do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} when byte_size(raw) == 32 -> {:ok, raw}
      _ -> {:error, :unauthenticated}
    end
  end

  def decode(_), do: {:error, :unauthenticated}

  defp find_active_user(raw, repository) do
    case repository.find_active_session(:crypto.hash(:sha256, raw), DateTime.utc_now()) do
      {:ok, user} -> {:ok, user}
      :not_found -> {:error, :unauthenticated}
      {:error, :unavailable} = error -> error
    end
  end
end
