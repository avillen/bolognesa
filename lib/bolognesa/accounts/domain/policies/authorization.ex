defmodule Bolognesa.Accounts.Domain.Policies.Authorization do
  @moduledoc "Access rules for verified actors."
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser

  @spec authorize(AuthenticatedUser.t() | nil, :admin) :: :ok | {:error, :forbidden}
  def authorize(%AuthenticatedUser{role: :admin}, :admin), do: :ok
  def authorize(_, :admin), do: {:error, :forbidden}
end
