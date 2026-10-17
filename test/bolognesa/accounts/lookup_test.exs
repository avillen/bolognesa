defmodule Bolognesa.Accounts.LookupTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Application.UseCases.FetchAuthenticatedAdmin
  alias Bolognesa.Accounts.Infrastructure.Repositories.EctoUserRepository, as: Repository

  defmodule UnavailableRepository do
    @spec fetch_admin() :: {:error, :unavailable}
    def fetch_admin, do: {:error, :unavailable}
  end

  test "administrator lookup preserves persistence failures" do
    assert {:error, :unavailable} = FetchAuthenticatedAdmin.call(UnavailableRepository)
  end

  test "missing account resources return not_found" do
    assert :not_found = Accounts.fetch_authenticated_admin()
    assert :not_found = Repository.fetch_admin()
    assert :not_found = Repository.fetch_user_by_email("missing@example.com")
    assert :not_found = Repository.fetch_active_session("missing", DateTime.utc_now())
  end

  test "account lookups return the resource inside an ok tuple" do
    assert {:ok, actor} =
             Accounts.install_admin(%{
               name: "Ada",
               email: "ada@example.com",
               password: "correct horse battery staple"
             })

    assert {:ok, ^actor} = Accounts.fetch_authenticated_admin()
    assert {:ok, ^actor} = Bolognesa.Release.fetch_authenticated_admin()
    assert {:ok, user} = Repository.fetch_admin()
    assert user.id == actor.id
    assert {:ok, {^user, hash}} = Repository.fetch_user_by_email(actor.email)
    assert Bcrypt.verify_pass("correct horse battery staple", hash)
  end
end
