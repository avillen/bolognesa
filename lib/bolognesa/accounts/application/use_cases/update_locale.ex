defmodule Bolognesa.Accounts.Application.UseCases.UpdateLocale do
  @moduledoc "Update the verified actor's own language preference."
  alias Bolognesa.Accounts.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Accounts.Domain.ValueObjects.Locale
  alias Bolognesa.Infrastructure.Observability.Events

  @spec call(AuthenticatedUser.t() | nil, Locale.t(), UserRepository.adapter()) ::
          {:ok, AuthenticatedUser.t()} | {:error, :forbidden | :invalid_locale | :unavailable}
  def call(%AuthenticatedUser{role: role} = actor, value, repository)
      when role in [:admin, :member] do
    with {:ok, locale} <- Locale.validate(value),
         {:ok, user} <- repository.update_locale(actor.id, locale) do
      Events.emit(:accounts, :preference, :completed, %{user_id: user.id, operation: :locale})
      {:ok, AuthenticatedUser.from_user(user)}
    else
      {:error, :unavailable} = error ->
        Events.emit(:accounts, :preference, :failed, %{
          user_id: actor.id,
          operation: :locale,
          reason: :storage_unavailable
        })

        error

      error ->
        error
    end
  end

  def call(_, _, _), do: {:error, :forbidden}
end
