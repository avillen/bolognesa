defmodule Bolognesa.Identity.Domain.Session do
  @moduledoc "A fixed lifetime session without sliding renewal."
  defstruct [:user_id, :token_hash, :expires_at]

  @type t :: %__MODULE__{user_id: integer(), token_hash: binary(), expires_at: DateTime.t()}

  @lifetime_seconds 30 * 24 * 60 * 60

  @spec new(integer(), binary(), DateTime.t()) :: t()
  def new(user_id, token_hash, now) do
    %__MODULE__{
      user_id: user_id,
      token_hash: token_hash,
      expires_at: DateTime.add(now, @lifetime_seconds, :second)
    }
  end
end
