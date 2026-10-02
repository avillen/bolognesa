defmodule Bolognesa.Identity.Application.StartSession do
  @moduledoc "Authenticate credentials and create a durable session."
  alias Bolognesa.Identity.Application.Ports.PasswordHasher
  alias Bolognesa.Identity.Application.Ports.Repository
  alias Bolognesa.Identity.Domain.Session
  alias Bolognesa.Identity.Domain.User

  @spec call(User.email(), User.password(), Repository.adapter(), PasswordHasher.adapter()) ::
          {:ok, Session.token()} | {:error, :invalid_credentials | :unavailable}
  def call(email, password, repository, hasher) when is_binary(email) and is_binary(password) do
    normalized_email = email |> String.trim() |> String.downcase()

    if byte_size(password) in 1..72 and :binary.match(password, <<0>>) == :nomatch do
      authenticate(normalized_email, password, repository, hasher)
    else
      hasher.dummy_verify(password)
      {:error, :invalid_credentials}
    end
  end

  def call(_, _, _repository, _hasher), do: {:error, :invalid_credentials}

  defp authenticate(email, password, repository, hasher) do
    case repository.find_user_by_email(email) do
      {:ok, user, hash} ->
        verify_and_start_session(user, password, hash, repository, hasher)

      :not_found ->
        hasher.dummy_verify(password)
        {:error, :invalid_credentials}

      {:error, :unavailable} = error ->
        error
    end
  end

  defp verify_and_start_session(user, password, hash, repository, hasher) do
    if hasher.verify(password, hash) do
      create_session(user, repository)
    else
      {:error, :invalid_credentials}
    end
  end

  defp create_session(user, repository) do
    raw = :crypto.strong_rand_bytes(32)
    token = Base.url_encode64(raw, padding: false)
    session = Session.new(user.id, :crypto.hash(:sha256, raw), DateTime.utc_now())

    case repository.insert_session(user.id, session.token_hash, session.expires_at) do
      :ok -> {:ok, token}
      {:error, :unavailable} = error -> error
    end
  end
end
