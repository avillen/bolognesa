defmodule Bolognesa.Accounts.Application.UseCases.InstallAdmin do
  @moduledoc "Install the sole initial administrator."
  alias Bolognesa.Accounts.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Accounts.Application.Ports.Services.PasswordHasher
  alias Bolognesa.Accounts.Domain.Entities.User
  alias Bolognesa.Accounts.Domain.ValueObjects.Sessions.NewAdmin
  alias Bolognesa.Infrastructure.Observability.Events

  @spec call(NewAdmin.attrs(), UserRepository.adapter(), PasswordHasher.adapter()) ::
          {:ok, User.t()}
          | {:error, {:invalid, NewAdmin.validation_errors()} | :setup_closed | :unavailable}
  def call(attrs, repository, hasher) do
    with {:ok, registration} <- NewAdmin.new(attrs) do
      result = repository.insert_initial_admin(registration, hasher.hash(registration.password))
      observe(result)
      result
    end
  end

  defp observe({:ok, user}), do: Events.emit(:accounts, :setup, :completed, %{user_id: user.id})

  defp observe({:error, :unavailable}),
    do: Events.emit(:accounts, :setup, :failed, %{reason: :storage_unavailable})

  defp observe(_), do: :ok
end
