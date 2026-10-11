defmodule Bolognesa.Identity.Domain.ValueObjects.Sessions.SessionToken do
  @moduledoc "Define the 256-bit browser token format and decode its URL-safe encoding."
  alias Bolognesa.Identity.Domain.ReadModels.Session

  @type raw_token :: binary()

  @raw_token_bytes 32
  # 32 bytes encode to 43 Base64url characters without padding.
  @encoded_token_bytes 43

  @spec raw_byte_length() :: pos_integer()
  def raw_byte_length, do: @raw_token_bytes

  @spec decode(Session.token() | nil) :: {:ok, raw_token()} | {:error, :unauthenticated}
  def decode(token) when is_binary(token) and byte_size(token) == @encoded_token_bytes do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} when byte_size(raw) == @raw_token_bytes -> {:ok, raw}
      _ -> {:error, :unauthenticated}
    end
  end

  def decode(_), do: {:error, :unauthenticated}
end
