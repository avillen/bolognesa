defmodule Bolognesa.Identity.Application.EndSession do
  @moduledoc "Revoke the current token only."
  alias Bolognesa.Identity.Application.Ports.Repository
  alias Bolognesa.Identity.Application.ResolveSession
  alias Bolognesa.Identity.Domain.Session

  @spec call(Session.token() | nil, Repository.adapter()) :: :ok | {:error, :unavailable}
  def call(token, repository) do
    case ResolveSession.decode(token) do
      {:ok, raw} -> repository.delete_session(:crypto.hash(:sha256, raw))
      {:error, :unauthenticated} -> :ok
    end
  end
end
