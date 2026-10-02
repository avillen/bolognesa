defmodule Bolognesa.Identity.Application.Ports.Repository do
  @moduledoc "Storage operations needed by identity use cases."
  alias Bolognesa.Identity.Domain.User

  @callback admin_exists?() :: {:ok, boolean()} | {:error, :unavailable}
  @callback insert_initial_admin(User.t(), binary()) ::
              {:ok, User.t()} | {:error, :setup_closed | :unavailable}
  @callback find_user_by_email(binary()) ::
              {:ok, User.t(), binary()} | :not_found | {:error, :unavailable}
  @callback insert_session(integer(), binary(), DateTime.t()) :: :ok | {:error, :unavailable}
  @callback find_active_session(binary(), DateTime.t()) ::
              {:ok, User.t()} | :not_found | {:error, :unavailable}
  @callback delete_session(binary()) :: :ok | {:error, :unavailable}
end
