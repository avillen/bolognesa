defmodule Bolognesa.Identity.Application.UseCases.InstallAdmin do
  @moduledoc "Install the sole initial administrator."
  alias Bolognesa.Identity.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Identity.Application.Ports.Services.PasswordHasher
  alias Bolognesa.Identity.Domain.Entities.User
  alias Bolognesa.Identity.Domain.ValueObjects.Sessions.NewAdmin

  @spec call(NewAdmin.attrs(), UserRepository.adapter(), PasswordHasher.adapter()) ::
          {:ok, User.t()}
          | {:error, {:invalid, NewAdmin.validation_errors()} | :setup_closed | :unavailable}
  def call(attrs, repository, hasher) do
    with {:ok, registration} <- NewAdmin.new(attrs) do
      repository.insert_initial_admin(registration, hasher.hash(registration.password))
    end
  end
end
