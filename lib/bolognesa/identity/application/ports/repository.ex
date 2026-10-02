defmodule Bolognesa.Identity.Application.Ports.Repository do
  @moduledoc "Storage operations needed by identity use cases."
  alias Bolognesa.Identity.Application.Ports.PasswordHasher
  alias Bolognesa.Identity.Domain.Session
  alias Bolognesa.Identity.Domain.User

  @typedoc "Module implementing the repository behaviour."
  @type adapter :: atom()

  @callback admin_exists?() :: {:ok, boolean()} | {:error, :unavailable}
  @callback insert_initial_admin(User.t(), PasswordHasher.hash()) ::
              {:ok, User.t()} | {:error, :setup_closed | :unavailable}
  @callback find_user_by_email(User.email()) ::
              {:ok, User.t(), PasswordHasher.hash()} | :not_found | {:error, :unavailable}
  @callback insert_session(User.id(), Session.token_hash(), Session.expires_at()) ::
              :ok | {:error, :unavailable}
  @callback find_active_session(Session.token_hash(), DateTime.t()) ::
              {:ok, User.t()} | :not_found | {:error, :unavailable}
  @callback delete_session(Session.token_hash()) :: :ok | {:error, :unavailable}
end
