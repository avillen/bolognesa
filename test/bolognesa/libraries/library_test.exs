defmodule Bolognesa.Libraries.LibraryTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Accounts.Domain.Entities.Actor
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Libraries
  alias Ecto.Adapters.SQL.Sandbox

  @admin %Actor{id: 1, name: "Ada", email: "ada@example.com", role: :admin}
  @member %Actor{id: 2, name: "Joe", email: "joe@example.com", role: :member}

  setup do
    root = Application.fetch_env!(:bolognesa, :library_roots) |> hd()
    File.mkdir_p!(root)
    path = Path.join(root, "source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    %{path: path}
  end

  test "creates and lists music libraries", %{path: path} do
    assert {:ok, library} =
             Libraries.create_library(@admin, %{name: "Music", path: path, content_type: :music})

    assert library.content_type == :music
    assert {:ok, [listed]} = Libraries.list_libraries(@admin)
    assert listed.content_type == :music
  end

  test "requires a known content type and persists series", %{path: path} do
    assert {:error, :invalid_content_type} =
             Libraries.create_library(@admin, %{name: "Series", path: path})

    assert {:error, :invalid_content_type} =
             Libraries.create_library(@admin, %{name: "Series", path: path, content_type: :mixed})

    assert {:ok, library} =
             Libraries.create_library(@admin, %{name: "Series", path: path, content_type: :series})

    assert library.content_type == :series
    assert {:ok, [listed]} = Libraries.list_libraries(@admin)
    assert listed.content_type == :series
  end

  test "stores a canonical source and lists it after another read", %{path: path} do
    assert {:ok, library} =
             Libraries.create_library(@admin, %{
               name: " Películas ",
               path: path <> "/.",
               content_type: :movie
             })

    assert library.name == "Películas"
    assert String.ends_with?(library.path, Path.basename(path))
    assert {:ok, [listed]} = Libraries.list_libraries(@admin)
    assert listed.id == library.id
  end

  test "rejects invalid, missing and out-of-root sources", %{path: path} do
    assert {:error, :invalid_name} =
             Libraries.create_library(@admin, %{name: " ", path: path, content_type: :movie})

    assert {:error, :invalid_path} =
             Libraries.create_library(@admin, %{name: "A", path: "relative", content_type: :movie})

    assert {:error, :invalid_name} =
             Libraries.create_library(@admin, %{"name" => "A", "path" => path})

    assert {:error, :invalid_name} =
             Libraries.create_library(@admin, %{name: <<255>>, path: path, content_type: :movie})

    assert {:error, :source_inaccessible} =
             Libraries.create_library(@admin, %{
               name: "A",
               path: path <> "/missing",
               content_type: :movie
             })

    assert {:error, :source_outside_roots} =
             Libraries.create_library(@admin, %{
               name: "A",
               path: System.tmp_dir!(),
               content_type: :movie
             })

    assert Repo.aggregate(LibrarySchema, :count) == 0
  end

  test "rejects symbolic links that escape an allowed root", %{path: path} do
    link = Path.join(path, "escape")
    File.ln_s!(System.tmp_dir!(), link)

    assert {:error, :source_outside_roots} =
             Libraries.create_library(@admin, %{name: "A", path: link, content_type: :movie})
  end

  test "rejects a directory without read permission", %{path: path} do
    File.chmod!(path, 0o000)

    try do
      assert {:error, :source_inaccessible} =
               Libraries.create_library(@admin, %{name: "A", path: path, content_type: :movie})
    after
      File.chmod!(path, 0o700)
    end
  end

  test "rejects a second registration of the same physical directory", %{path: path} do
    assert {:ok, _} =
             Libraries.create_library(@admin, %{name: "One", path: path, content_type: :movie})

    assert {:error, :duplicate_source} =
             Libraries.create_library(@admin, %{
               name: "Two",
               path: path <> "/.",
               content_type: :movie
             })

    assert Repo.aggregate(LibrarySchema, :count) == 1
  end

  test "a symbolic alias of a registered directory is also a duplicate", %{path: path} do
    alias_path = path <> "-alias"
    File.ln_s!(path, alias_path)
    on_exit(fn -> File.rm(alias_path) end)

    assert {:ok, _} =
             Libraries.create_library(@admin, %{name: "One", path: path, content_type: :movie})

    assert {:error, :duplicate_source} =
             Libraries.create_library(@admin, %{
               name: "Two",
               path: alias_path,
               content_type: :movie
             })
  end

  test "simultaneous registrations create one library", %{path: path} do
    supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    try do
      tasks =
        for name <- ["One", "Two"] do
          Task.Supervisor.async_nolink(supervisor, fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(parent, {:ready, self()})

              receive do
                :go ->
                  Libraries.create_library(@admin, %{name: name, path: path, content_type: :movie})
              end
            end)
          end)
        end

      pids =
        for _ <- tasks do
          assert_receive {:ready, pid}
          pid
        end

      Enum.each(pids, &send(&1, :go))
      results = Enum.map(tasks, &Task.await/1)
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :duplicate_source})) == 1

      assert Sandbox.unboxed_run(Repo, fn ->
               Repo.aggregate(LibrarySchema, :count)
             end) == 1
    after
      Sandbox.unboxed_run(Repo, fn -> Repo.delete_all(LibrarySchema) end)
    end
  end

  test "requires an administrator for writes and reads", %{path: path} do
    assert {:error, :forbidden} =
             Libraries.create_library(@member, %{name: "A", path: path, content_type: :movie})

    assert {:error, :forbidden} = Libraries.list_libraries(@member)
    assert {:error, :forbidden} = Libraries.list_libraries(nil)
  end
end
