defmodule Bolognesa.Accounts.Application.UseCases.GetAdminActor do
  @moduledoc "Resolve the administrator for the trusted release console."
  alias Bolognesa.Accounts.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Accounts.Domain.Entities.Actor

  @spec call(UserRepository.adapter()) :: Actor.t() | nil
  def call(repository) do
    case repository.find_admin() do
      nil -> nil
      user -> Actor.from_user(user)
    end
  end
end
