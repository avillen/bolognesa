defmodule Bolognesa.Accounts.Application.UseCases.FetchAuthenticatedAdmin do
  @moduledoc "Resolve the administrator for the trusted release console."
  alias Bolognesa.Accounts.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser

  @spec call(UserRepository.adapter()) ::
          {:ok, AuthenticatedUser.t()} | :not_found | {:error, :unavailable}
  def call(repository) do
    with {:ok, user} <- repository.fetch_admin() do
      {:ok, AuthenticatedUser.from_user(user)}
    end
  end
end
