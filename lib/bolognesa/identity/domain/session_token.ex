defmodule Bolognesa.Identity.Domain.SessionToken do
  @moduledoc "Define the 256-bit browser token format and decode its URL-safe encoding."
  alias Bolognesa.Identity.Domain.Session

  @type raw_token :: binary()

  @raw_token_bytes 32
  @encoded_token_bytes byte_size(
                         Base.url_encode64(:binary.copy(<<0>>, @raw_token_bytes), padding: false)
                       )

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
