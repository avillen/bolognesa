defmodule Bolognesa.Accounts.Application.UseCases.InstallAdmin do
  @moduledoc "Install the sole initial administrator."
  alias Bolognesa.Accounts.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Accounts.Application.Ports.Services.PasswordHasher
  alias Bolognesa.Accounts.Domain.Entities.User
  alias Bolognesa.Accounts.Domain.ValueObjects.Sessions.NewAdmin

  @spec call(NewAdmin.attrs(), UserRepository.adapter(), PasswordHasher.adapter()) ::
          {:ok, User.t()}
          | {:error, {:invalid, NewAdmin.validation_errors()} | :setup_closed | :unavailable}
  def call(attrs, repository, hasher) do
    with {:ok, registration} <- NewAdmin.new(attrs) do
      repository.insert_initial_admin(registration, hasher.hash(registration.password))
    end
  end
end
