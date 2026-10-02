defmodule Bolognesa.Identity.Application.InstallAdmin do
  @moduledoc "Install the sole initial administrator."
  alias Bolognesa.Identity.Domain.User

  def call(attrs, repository, hasher) do
    with {:ok, user} <- User.new_admin(attrs) do
      password = Map.get(attrs, :password) || Map.get(attrs, "password")
      repository.insert_initial_admin(user, hasher.hash(password))
    end
  end
end
