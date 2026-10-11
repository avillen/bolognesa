defmodule Bolognesa.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :bolognesa
  import Ecto.Query

  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identity.Infrastructure.Repositories.EctoUserRepository.UserMapper
  alias Bolognesa.Infrastructure.Persistence.UserSchema
  alias Bolognesa.Repo

  @spec admin_actor() :: Actor.t() | nil
  def admin_actor do
    query =
      from user in UserSchema, where: user.role == "admin", select: [:id, :name, :email, :role]

    case Repo.one(query) do
      nil -> nil
      user -> user |> UserMapper.to_user() |> Actor.from_user()
    end
  end

  @spec migrate() :: [{:ok, [integer()], [atom()]}]
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @spec rollback(Bolognesa.Repo, non_neg_integer()) :: {:ok, [integer()], [atom()]}
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
