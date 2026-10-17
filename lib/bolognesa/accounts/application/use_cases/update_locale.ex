defmodule Bolognesa.Accounts.Application.UseCases.UpdateLocale do
  @moduledoc "Update the verified actor's own language preference."
  alias Bolognesa.Accounts.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Accounts.Domain.ValueObjects.Locale

  @spec call(AuthenticatedUser.t() | nil, Locale.t(), UserRepository.adapter()) ::
          {:ok, AuthenticatedUser.t()} | {:error, :forbidden | :invalid_locale | :unavailable}
  def call(%AuthenticatedUser{role: role} = actor, value, repository)
      when role in [:admin, :member] do
    with {:ok, locale} <- Locale.validate(value),
         {:ok, user} <- repository.update_locale(actor.id, locale) do
      {:ok, AuthenticatedUser.from_user(user)}
    end
  end

  def call(_, _, _), do: {:error, :forbidden}
end
