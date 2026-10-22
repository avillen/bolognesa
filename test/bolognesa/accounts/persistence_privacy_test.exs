defmodule Bolognesa.Accounts.PersistencePrivacyTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Accounts.Domain.Entities.Session
  alias Bolognesa.Accounts.Domain.ValueObjects.Sessions.NewAdmin
  alias Bolognesa.Accounts.Infrastructure.Repositories.EctoUserRepository, as: Repository

  test "account and session persistence keeps credential hashes out of SQL logs" do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)

    password_hash = "synthetic-password-hash-marker"
    token_hash = "synthetic-session-hash-marker"

    {:ok, admin} =
      NewAdmin.new(%{name: "Sample", email: "sample@example.com", password: "Long password 123!"})

    log =
      ExUnit.CaptureLog.capture_log([level: :debug], fn ->
        assert {:ok, user} = Repository.insert_initial_admin(admin, password_hash)
        assert {:ok, {_, ^password_hash}} = Repository.fetch_user_by_email(admin.email)
        session = Session.new(user.id, token_hash, DateTime.utc_now())
        assert :ok = Repository.insert_session(session)
        assert {:ok, _} = Repository.fetch_active_session(token_hash, session.issued_at)
        assert {:ok, :deleted} = Repository.delete_session(token_hash)
      end)

    refute log =~ password_hash
    refute log =~ token_hash
  end
end
