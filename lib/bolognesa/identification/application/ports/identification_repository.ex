defmodule Bolognesa.Identification.Application.Ports.IdentificationRepository do
  @moduledoc "Persistence boundary for identification transitions."
  alias Bolognesa.Identification.Domain.{Identification, MovieCandidate, MovieDetails}
  alias Bolognesa.Libraries.Domain.MediaFile

  @callback begin_identification(pos_integer(), binary(), integer() | nil) ::
              {:ok, :stale | MediaFile.t()} | {:error, :unavailable}
  @callback complete(
              pos_integer(),
              binary(),
              [MovieCandidate.t()],
              MovieDetails.t() | nil,
              boolean()
            ) ::
              :ok | {:ok, :stale} | {:error, atom()}
  @callback fail(pos_integer(), binary(), atom()) ::
              :ok | {:ok, :stale} | {:error, atom()}
  @callback correct(pos_integer(), :unidentified | MovieDetails.t()) ::
              {:ok, Identification.t()} | {:error, atom()}
  @callback retry(pos_integer()) :: {:ok, Identification.t()} | {:error, atom()}
end
