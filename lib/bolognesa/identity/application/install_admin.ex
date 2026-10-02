defmodule Bolognesa.Identity.Application.InstallAdmin do
  @moduledoc "Install the sole initial administrator."
  alias Bolognesa.Identity.Application.Ports.PasswordHasher
  alias Bolognesa.Identity.Application.Ports.Repository
  alias Bolognesa.Identity.Domain.User

  @spec call(User.admin_attrs(), Repository.adapter(), PasswordHasher.adapter()) ::
          {:ok, User.t()}
          | {:error, {:invalid, User.validation_errors()} | :setup_closed | :unavailable}
  def call(attrs, repository, hasher) do
    with {:ok, user} <- User.new_admin(attrs) do
      password = Map.get(attrs, :password) || Map.get(attrs, "password")
      repository.insert_initial_admin(user, hasher.hash(password))
    end
  end
end
