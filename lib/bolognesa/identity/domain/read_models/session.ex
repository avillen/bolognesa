defmodule Bolognesa.Identity.Domain.ReadModels.Session do
  @moduledoc "A fixed lifetime session without sliding renewal."
  alias Bolognesa.Identity.Domain.Entities.User

  @type token :: String.t()
  @type token_hash :: binary()
  @type issued_at :: DateTime.t()
  @type expires_at :: DateTime.t()

  @type t :: %__MODULE__{
          user_id: User.id(),
          token_hash: token_hash(),
          expires_at: expires_at()
        }

  defstruct [:user_id, :token_hash, :expires_at]

  @lifetime_seconds 30 * 24 * 60 * 60

  @spec new(User.id(), token_hash(), issued_at()) :: t()
  def new(user_id, token_hash, now) do
    %__MODULE__{
      user_id: user_id,
      token_hash: token_hash,
      expires_at: DateTime.add(now, @lifetime_seconds, :second)
    }
  end
end
