defmodule Bolognesa.Identification.Application.Ports.IdentificationRepository do
  @moduledoc "Persistence boundary for identification transitions."
  alias Bolognesa.Identification.Domain.Identification

  @callback begin_identification(pos_integer(), binary(), integer() | nil) ::
              {:ok, :stale | map()} | {:error, atom()}
  @callback complete(pos_integer(), binary(), list(), map() | nil, boolean()) ::
              :ok | {:ok, :stale} | {:error, atom()}
  @callback fail(pos_integer(), binary(), atom()) ::
              :ok | {:ok, :stale} | {:error, atom()}
  @callback correct(pos_integer(), :unidentified | map()) ::
              {:ok, Identification.t()} | {:error, atom()}
  @callback retry(pos_integer()) :: {:ok, Identification.t()} | {:error, atom()}
end
