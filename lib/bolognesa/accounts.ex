defmodule Bolognesa.Accounts do
  @moduledoc "Public accounts and access facade."
  alias Bolognesa.Accounts.Application.UseCases.{
    EndSession,
    FetchAuthenticatedAdmin,
    InstallAdmin,
    ResolveSession,
    StartSession,
    UpdateLocale
  }

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Accounts.Domain.Entities.Session
  alias Bolognesa.Accounts.Domain.Entities.User
  alias Bolognesa.Accounts.Domain.Policies.Authorization
  alias Bolognesa.Accounts.Domain.ValueObjects.Locale
  alias Bolognesa.Accounts.Domain.ValueObjects.Sessions.NewAdmin
  alias Bolognesa.Accounts.Infrastructure.Repositories.EctoUserRepository
  alias Bolognesa.Accounts.Infrastructure.Services.BcryptHasher

  @spec setup_status() :: {:ok, :open | :closed} | {:error, :unavailable}
  def setup_status do
    case EctoUserRepository.admin_exists?() do
      {:ok, true} -> {:ok, :closed}
      {:ok, false} -> {:ok, :open}
      {:error, :unavailable} = error -> error
    end
  end

  @spec install_admin(NewAdmin.attrs()) ::
          {:ok, AuthenticatedUser.t()}
          | {:error, {:invalid, NewAdmin.validation_errors()} | :setup_closed | :unavailable}
  def install_admin(attrs) do
    with {:ok, user} <- InstallAdmin.call(attrs, EctoUserRepository, BcryptHasher) do
      {:ok, AuthenticatedUser.from_user(user)}
    end
  end

  @spec authorize(AuthenticatedUser.t() | nil, :admin) :: :ok | {:error, :forbidden}
  def authorize(actor, permission), do: Authorization.authorize(actor, permission)

  @spec fetch_authenticated_admin() ::
          {:ok, AuthenticatedUser.t()} | :not_found | {:error, :unavailable}
  def fetch_authenticated_admin, do: FetchAuthenticatedAdmin.call(EctoUserRepository)

  @spec start_session(User.email(), User.password()) ::
          {:ok, Session.token()} | {:error, :invalid_credentials | :unavailable}
  def start_session(email, password),
    do: StartSession.call(email, password, EctoUserRepository, BcryptHasher)

  @spec fetch_authenticated_user(Session.token() | nil) ::
          {:ok, AuthenticatedUser.t()} | {:error, :unauthenticated | :unavailable}
  def fetch_authenticated_user(token), do: ResolveSession.call(token, EctoUserRepository)

  @spec update_locale(AuthenticatedUser.t() | nil, Locale.t()) ::
          {:ok, AuthenticatedUser.t()} | {:error, :forbidden | :invalid_locale | :unavailable}
  def update_locale(actor, locale), do: UpdateLocale.call(actor, locale, EctoUserRepository)

  @spec end_session(Session.token() | nil) :: :ok | {:error, :unavailable}
  def end_session(token), do: EndSession.call(token, EctoUserRepository)
end
