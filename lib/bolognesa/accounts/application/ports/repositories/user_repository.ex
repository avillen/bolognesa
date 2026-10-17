defmodule Bolognesa.Accounts.Application.Ports.Repositories.UserRepository do
  @moduledoc "Storage operations needed by account use cases."
  alias Bolognesa.Accounts.Application.Ports.Services.PasswordHasher
  alias Bolognesa.Accounts.Domain.Entities.Session
  alias Bolognesa.Accounts.Domain.Entities.User
  alias Bolognesa.Accounts.Domain.ValueObjects.Locale
  alias Bolognesa.Accounts.Domain.ValueObjects.Sessions.NewAdmin

  @typedoc "Module implementing the repository behaviour."
  @type adapter :: atom()

  @typedoc "Account and password hash used to verify credentials."
  @type user_credentials :: {User.t(), PasswordHasher.hash()}

  @callback update_locale(User.id(), Locale.t()) :: {:ok, User.t()} | {:error, :unavailable}
  @callback admin_exists?() :: {:ok, boolean()} | {:error, :unavailable}
  @callback insert_initial_admin(NewAdmin.t(), PasswordHasher.hash()) ::
              {:ok, User.t()} | {:error, :setup_closed | :unavailable}
  @callback fetch_user_by_email(User.email()) ::
              {:ok, user_credentials()} | :not_found | {:error, :unavailable}
  @callback fetch_admin() :: {:ok, User.t()} | :not_found | {:error, :unavailable}
  @callback insert_session(Session.t()) ::
              :ok | {:error, :unavailable}
  @callback fetch_active_session(Session.token_hash(), DateTime.t()) ::
              {:ok, User.t()} | :not_found | {:error, :unavailable}
  @callback delete_session(Session.token_hash()) :: :ok | {:error, :unavailable}
end
