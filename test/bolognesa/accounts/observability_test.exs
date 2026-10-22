defmodule Bolognesa.Accounts.ObservabilityTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Accounts

  alias Bolognesa.Accounts.Application.UseCases.{
    EndSession,
    InstallAdmin,
    ResolveSession,
    StartSession,
    UpdateLocale
  }

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser

  defmodule UnavailableRepository do
    def fetch_active_session(_, _), do: {:error, :unavailable}
    def fetch_user_by_email(_), do: {:error, :unavailable}
    def insert_initial_admin(_, _), do: {:error, :unavailable}
    def delete_session(_), do: {:error, :unavailable}
    def update_locale(_, _), do: {:error, :unavailable}
  end

  defmodule Hasher do
    def hash(_), do: "private-hash"
  end

  setup do
    owner = self()
    handler = {__MODULE__, make_ref()}

    events =
      for resource <- [:setup, :session, :preference],
          outcome <- [:completed, :failed, :rejected],
          do: [:bolognesa, :accounts, resource, outcome]

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        fn event, measurements, metadata, _ ->
          send(owner, {:event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  test "mutations report safe milestones while ordinary resolution and no-op logout stay quiet" do
    assert {:ok, user} =
             Accounts.install_admin(%{
               name: "private-name",
               email: "private@example.com",
               password: "private-password"
             })

    assert_receive {:event, [:bolognesa, :accounts, :setup, :completed], _, %{user_id: user_id}}
    assert user_id == user.id
    assert {:ok, token} = Accounts.start_session("private@example.com", "private-password")

    assert_receive {:event, [:bolognesa, :accounts, :session, :completed], _,
                    %{operation: :start, user_id: ^user_id} = metadata}

    refute inspect(metadata) =~ "private"
    refute inspect(metadata) =~ token
    assert {:ok, _} = Accounts.fetch_authenticated_user(token)
    refute_receive {:event, _, _, _}
    assert :ok = Accounts.end_session(token)

    assert_receive {:event, [:bolognesa, :accounts, :session, :completed], _,
                    %{operation: :revoke, result: :deleted}}

    assert :ok = Accounts.end_session(token)
    assert :ok = Accounts.end_session(nil)
    refute_receive {:event, _, _, _}
  end

  test "preference completion follows the confirmed write" do
    assert {:ok, user} =
             Accounts.install_admin(%{
               name: "Sample",
               email: "sample@example.com",
               password: "private-password"
             })

    assert_receive {:event, [:bolognesa, :accounts, :setup, :completed], _, _}
    assert {:ok, updated} = Accounts.update_locale(user, "es")
    assert updated.locale == "es"

    assert_receive {:event, [:bolognesa, :accounts, :preference, :completed], _,
                    %{user_id: user_id, operation: :locale}}

    assert user_id == user.id
  end

  test "persistence failures are observed without claiming completed writes" do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    actor = %AuthenticatedUser{id: 17, role: :admin, locale: "en"}
    assert {:error, :unavailable} = ResolveSession.call(token, UnavailableRepository)

    assert_receive {:event, [:bolognesa, :accounts, :session, :failed], _,
                    %{operation: :resolve, reason: :storage_unavailable}}

    assert {:error, :unavailable} =
             StartSession.call(
               "private@example.com",
               "private-password",
               UnavailableRepository,
               Hasher
             )

    assert_receive {:event, [:bolognesa, :accounts, :session, :failed], _,
                    %{operation: :start, reason: :storage_unavailable}}

    assert {:error, :unavailable} = EndSession.call(token, UnavailableRepository)

    assert_receive {:event, [:bolognesa, :accounts, :session, :failed], _,
                    %{operation: :revoke, reason: :storage_unavailable}}

    assert {:error, :unavailable} = UpdateLocale.call(actor, "es", UnavailableRepository)

    assert_receive {:event, [:bolognesa, :accounts, :preference, :failed], _,
                    %{user_id: 17, reason: :storage_unavailable}}

    assert {:error, :unavailable} =
             InstallAdmin.call(
               %{name: "Sample", email: "private@example.com", password: "private-password"},
               UnavailableRepository,
               Hasher
             )

    assert_receive {:event, [:bolognesa, :accounts, :setup, :failed], _,
                    %{reason: :storage_unavailable}}

    refute_receive {:event, [:bolognesa, :accounts, _, :completed], _, _}
  end

  test "invalid credentials have a distinct safe rejection observation" do
    assert {:error, :invalid_credentials} =
             Accounts.start_session("private@example.com", "private-secret")

    assert_receive {:event, [:bolognesa, :accounts, :session, :rejected], _,
                    %{reason: :invalid_credentials} = metadata}

    refute inspect(metadata) =~ "private"
  end
end
