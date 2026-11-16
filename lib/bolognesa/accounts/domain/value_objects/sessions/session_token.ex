defmodule Bolognesa.Accounts.Domain.ValueObjects.Sessions.SessionToken do
  @moduledoc "Define the 256-bit browser token format, its URL-safe encoding, and its stored hash."
  alias Bolognesa.Accounts.Domain.Entities.Session

  @type raw_token :: binary()

  @raw_token_bytes 32
  # 32 bytes encode to 43 Base64url characters without padding.
  @encoded_token_bytes 43

  @spec raw_byte_length() :: pos_integer()
  def raw_byte_length, do: @raw_token_bytes

  @spec hash(raw_token()) :: Session.token_hash()
  def hash(raw), do: :crypto.hash(:sha256, raw)

  @spec decode(Session.token() | nil) :: {:ok, Session.token_hash()} | {:error, :unauthenticated}
  def decode(token) when is_binary(token) and byte_size(token) == @encoded_token_bytes do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} when byte_size(raw) == @raw_token_bytes -> {:ok, hash(raw)}
      _ -> {:error, :unauthenticated}
    end
  end

  def decode(_), do: {:error, :unauthenticated}
end
