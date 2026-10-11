defmodule Bolognesa.Identity.Application.UseCases.UpdateLocale do
  @moduledoc "Update the verified actor's own language preference."
  alias Bolognesa.Identity.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Identity.Domain.ValueObjects.Locale

  @spec call(Actor.t() | nil, Locale.t(), UserRepository.adapter()) ::
          {:ok, Actor.t()} | {:error, :forbidden | :invalid_locale | :unavailable}
  def call(%Actor{role: role} = actor, value, repository) when role in [:admin, :member] do
    with {:ok, locale} <- Locale.validate(value),
         {:ok, user} <- repository.update_locale(actor.id, locale) do
      {:ok, Actor.from_user(user)}
    end
  end

  def call(_, _, _), do: {:error, :forbidden}
end
