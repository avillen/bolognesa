defmodule Bolognesa.Identity.Domain.SessionToken do
  @moduledoc "Decode the fixed format of a browser session token."
  alias Bolognesa.Identity.Domain.Session

  @type raw_token :: binary()

  @spec decode(Session.token() | nil) :: {:ok, raw_token()} | {:error, :unauthenticated}
  def decode(token) when is_binary(token) and byte_size(token) == 43 do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} when byte_size(raw) == 32 -> {:ok, raw}
      _ -> {:error, :unauthenticated}
    end
  end

  def decode(_), do: {:error, :unauthenticated}
end
