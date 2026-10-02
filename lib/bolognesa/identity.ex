defmodule Bolognesa.Identity do
  @moduledoc "Public identity and access facade."
  alias Bolognesa.Identity.Application.InstallAdmin
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identity.Infrastructure.BcryptHasher
  alias Bolognesa.Identity.Infrastructure.Persistence.{EctoRepository, UserMapper}

  def setup_status do
    case EctoRepository.admin_exists?() do
      {:ok, true} -> {:ok, :closed}
      {:ok, false} -> {:ok, :open}
      {:error, :unavailable} = error -> error
    end
  end

  def install_admin(attrs) do
    with {:ok, user} <- InstallAdmin.call(attrs, EctoRepository, BcryptHasher) do
      {:ok, UserMapper.to_actor(user)}
    end
  end

  def authorize(%Actor{role: :admin}, :admin), do: :ok
  def authorize(_, :admin), do: {:error, :forbidden}
end
