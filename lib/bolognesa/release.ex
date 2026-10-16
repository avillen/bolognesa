defmodule Bolognesa.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :bolognesa
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.Actor

  @spec admin_actor() :: Actor.t() | nil
  def admin_actor, do: Accounts.admin_actor()

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
