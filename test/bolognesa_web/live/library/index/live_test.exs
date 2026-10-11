defmodule BolognesaWeb.Library.Index.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  alias BolognesaWeb.Library.Index.Live
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker
  alias Bolognesa.Repo
  use Oban.Testing, repo: Bolognesa.Repo

  setup do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "ada@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("ada@example.com", "correct horse battery staple")
    root = Application.fetch_env!(:bolognesa, :library_roots) |> hd()
    path = Path.join(root, "web-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    {:ok, actor} = Identity.fetch_actor(token)
    %{token: token, path: path, actor: actor}
  end

  test "administrator adds a source and sees it after reconnecting", %{
    conn: conn,
    token: token,
    path: path
  } do
    conn = init_test_session(conn, user_token: token)
    {:ok, view, _} = live(conn, ~p"/libraries")
    assert has_element?(view, "#library-form")
    assert has_element?(view, "#libraries-empty")
    view |> form("#library-form", library: %{name: "Películas", path: path}) |> render_submit()
    assert has_element?(view, "#library-list [data-library-name='Películas']")
    {:ok, reopened, _} = live(conn, ~p"/libraries")
    assert has_element?(reopened, "#library-list [data-library-name='Películas']")

    {:ok, new_token} = Identity.start_session("ada@example.com", "correct horse battery staple")
    new_conn = Phoenix.ConnTest.build_conn() |> init_test_session(user_token: new_token)
    {:ok, new_session, _} = live(new_conn, ~p"/libraries")
    assert has_element?(new_session, "#library-list [data-library-name='Películas']")
  end

  test "duplicate source keeps the form and shows feedback", %{
    conn: conn,
    token: token,
    path: path
  } do
    conn = init_test_session(conn, user_token: token)
    {:ok, view, _} = live(conn, ~p"/libraries")
    view |> form("#library-form", library: %{name: "One", path: path}) |> render_submit()
    view |> form("#library-form", library: %{name: "Two", path: path}) |> render_submit()
    assert has_element?(view, "#library-error")
    assert has_element?(view, "#library-list [data-library-name='One']")
  end

  test "anonymous visitors cannot open libraries", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/libraries")
  end

  test "scan is queued durably and remains visible after reconnect", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    {:ok, library} = Libraries.create_library(actor, %{name: "Scan", path: path})
    conn = init_test_session(conn, user_token: token)
    {:ok, view, _} = live(conn, ~p"/libraries")
    render_async(view)
    view |> element("#library-scan-#{library.id}") |> render_click()
    assert has_element?(view, "#library-scan-#{library.id}[disabled]")
    assert has_element?(view, "#library-scan-state-#{library.id}[data-state='queued']")
    assert {:ok, %{latest_scan: scan}} = Libraries.get_scan_status(actor, library.id)
    assert_enqueued(worker: ScanWorker, args: %{scan_id: scan.id})
    {:ok, reopened, _} = live(conn, ~p"/libraries")
    render_async(reopened)
    assert has_element?(reopened, "#library-scan-state-#{library.id}[data-state='queued']")
  end

  test "manual drain completes discovery and refresh shows the last success", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    File.write!(Path.join(path, "movie.MKV"), "video")
    {:ok, library} = Libraries.create_library(actor, %{name: "Complete", path: path})
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    render_async(view)
    view |> element("#library-scan-#{library.id}") |> render_click()
    render_async(view)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)
    send(view.pid, :refresh_scan_statuses)
    render_async(view)
    assert has_element?(view, "#library-scan-state-#{library.id}[data-state='completed']")
    assert has_element?(view, "#library-scan-count-#{library.id}", "1 archivos")
    assert has_element?(view, "#library-scan-completed-#{library.id}")
    refute has_element?(view, "#library-scan-#{library.id}[disabled]")
  end

  test "shows inspection counts and requests a confirmed forced scan", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    File.write!(Path.join(path, "movie.mkv"), "video")
    {:ok, library} = Libraries.create_library(actor, %{name: "Technical", path: path})
    {:ok, first_scan} = Libraries.start_scan(actor, library.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    render_async(view)
    assert has_element?(view, "#library-inspection-counts-#{library.id}[data-pending='1']")
    view |> element("#library-reinspect-#{library.id}") |> render_click()
    assert has_element?(view, "#library-reinspect-confirm-#{library.id}")
    view |> element("#library-reinspect-confirm-button-#{library.id}") |> render_click()
    assert has_element?(view, "#library-scan-state-#{library.id}[data-state='queued']")
    assert has_element?(view, "#library-reinspect-#{library.id}[disabled]")
    assert {:ok, %{latest_scan: forced}} = Libraries.get_scan_status(actor, library.id)
    assert forced.id != first_scan.id
    assert forced.force_inspection?

    {:ok, reopened, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    render_async(reopened)
    assert has_element?(reopened, "#library-inspection-counts-#{library.id}")
    assert has_element?(reopened, "#library-reinspect-#{library.id}[disabled]")
  end

  test "refresh and reconnect show grouped technical failure reasons", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    for name <- ["first.mkv", "second.mkv", "third.mkv"] do
      File.write!(Path.join(path, name), "not media")
    end

    {:ok, library} = Libraries.create_library(actor, %{name: "Broken", path: path})
    {:ok, _} = Libraries.start_scan(actor, library.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)

    InspectionSchema
    |> Repo.all()
    |> Enum.with_index()
    |> Enum.each(fn {inspection, index} ->
      reason = if index == 2, do: :source_changed, else: :invalid_output

      inspection
      |> InspectionSchema.changeset(%{state: :failed, failure_reason: reason})
      |> Repo.update!()
    end)

    conn = init_test_session(conn, user_token: token)
    {:ok, view, _} = live(conn, ~p"/libraries")
    render_async(view)

    assert has_element?(
             view,
             "#library-inspection-counts-#{library.id}[data-failed='3']",
             "3 análisis técnicos con error"
           )

    assert has_element?(
             view,
             "#library-inspection-failure-#{library.id}-invalid_output",
             "2 · No se pudieron interpretar los datos técnicos"
           )

    assert has_element?(
             view,
             "#library-inspection-failure-#{library.id}-source_changed",
             "1 · El archivo cambió desde el escaneo"
           )

    assert has_element?(
             view,
             "#library-inspection-help-#{library.id}",
             "Esto no confirma un problema de reproducción"
           )

    {:ok, reopened, _} = live(conn, ~p"/libraries")
    render_async(reopened)
    assert has_element?(reopened, "#library-inspection-counts-#{library.id}[data-failed='3']")
    assert has_element?(reopened, "#library-inspection-failure-#{library.id}-invalid_output")
    assert has_element?(reopened, "#library-inspection-failure-#{library.id}-source_changed")
  end

  @tag capture_log: true
  test "failed scan can be retried and leaving the page does not cancel its job", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    {:ok, library} = Libraries.create_library(actor, %{name: "Retry", path: path})
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    render_async(view)
    view |> element("#library-scan-#{library.id}") |> render_click()
    render_async(view)
    File.rmdir!(path)
    assert %{cancelled: 1} = Oban.drain_queue(queue: :library_scans)
    send(view.pid, :refresh_scan_statuses)
    render_async(view)
    assert has_element?(view, "#library-scan-error-#{library.id}")
    assert has_element?(view, "#library-scan-#{library.id}", "Reintentar")
    File.mkdir_p!(path)
    view |> element("#library-scan-#{library.id}") |> render_click()

    assert {:ok, %{latest_scan: %{state: :queued} = scan}} =
             Libraries.get_scan_status(actor, library.id)

    ref = Process.monitor(view.pid)
    GenServer.stop(view.pid)
    assert_receive {:DOWN, ^ref, :process, _, _}
    assert_enqueued(worker: ScanWorker, args: %{scan_id: scan.id})
  end

  test "invalid and missing library clicks produce feedback without a job", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    render_async(view)

    for id <- ["0", "-1", "1oops", "999999999"] do
      render_click(view, "scan", %{"library_id" => id})
      assert has_element?(view, "#library-scan-feedback")
      render_async(view)
    end

    refute_enqueued(worker: ScanWorker)
  end

  test "stale status replies and update failures preserve rendered rows", %{
    path: path,
    actor: actor
  } do
    alias BolognesaWeb.Library.Index.Reducers.{ApplyScanStatuses, Initialize}
    alias Live
    {:ok, library} = Libraries.create_library(actor, %{name: "Retained", path: path})
    {:ok, _scan} = Libraries.start_scan(actor, library.id)
    {:ok, status} = Libraries.get_scan_status(actor, library.id)
    {:ok, counts} = Libraries.get_inspection_counts(actor, library.id)

    socket =
      %Phoenix.LiveView.Socket{
        endpoint: BolognesaWeb.Endpoint,
        private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}},
        assigns: %{__changed__: %{}, flash: %{}}
      }
      |> Phoenix.Component.assign(:current_scope, %{actor: actor})
      |> Initialize.call()

    request_id = socket.assigns.scan_request_id
    socket = ApplyScanStatuses.call(socket, request_id, {:ok, {:ok, [{library, status, counts}]}})
    socket = ApplyScanStatuses.call(socket, make_ref(), {:ok, {:ok, []}})
    socket = ApplyScanStatuses.call(socket, request_id, {:ok, {:error, :unavailable}})
    html = render_component(&Live.render/1, Map.put(socket.assigns, :__changed__, nil))
    document = LazyHTML.from_fragment(html)

    assert LazyHTML.query(document, "#library-scan-state-#{library.id}[data-state='queued']")
           |> LazyHTML.to_tree() != []

    assert LazyHTML.query(document, "#library-scan-feedback") |> LazyHTML.to_tree() != []
    assert {:ok, %{latest_scan: %{state: :queued}}} = Libraries.get_scan_status(actor, library.id)
  end

  test "scan reducer delegates authorization and creates no unauthorized job", %{
    path: path,
    actor: actor
  } do
    alias BolognesaWeb.Library.Index.Reducers.{Initialize, StartScan}
    {:ok, library} = Libraries.create_library(actor, %{name: "Authorized", path: path})

    socket =
      %Phoenix.LiveView.Socket{
        endpoint: BolognesaWeb.Endpoint,
        private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}},
        assigns: %{__changed__: %{}, flash: %{}}
      }
      |> Phoenix.Component.assign(:current_scope, %{actor: actor})
      |> Initialize.call()
      |> Phoenix.Component.assign(:current_scope, %{actor: nil})
      |> StartScan.call(Integer.to_string(library.id))

    html =
      render_component(
        &Live.render/1,
        Map.put(socket.assigns, :__changed__, nil)
      )

    assert LazyHTML.from_fragment(html)
           |> LazyHTML.query("#library-scan-feedback")
           |> LazyHTML.to_tree() != []

    refute_enqueued(worker: ScanWorker)
  end

  test "saving a new source invalidates an older status response", %{path: path, actor: actor} do
    alias BolognesaWeb.Library.Index.Reducers.{ApplyScanStatuses, Initialize, Save}

    socket =
      %Phoenix.LiveView.Socket{
        endpoint: BolognesaWeb.Endpoint,
        private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}},
        assigns: %{__changed__: %{}, flash: %{}}
      }
      |> Phoenix.Component.assign(:current_scope, %{actor: actor})
      |> Initialize.call()

    old_request = socket.assigns.scan_request_id
    socket = Save.call(socket, %{"name" => "New source", "path" => path})
    refute socket.assigns.scan_request_id == old_request
    socket = ApplyScanStatuses.call(socket, old_request, {:ok, {:ok, []}})

    html =
      render_component(
        &Live.render/1,
        Map.put(socket.assigns, :__changed__, nil)
      )

    assert LazyHTML.from_fragment(html)
           |> LazyHTML.query("#library-list [data-library-name='New source']")
           |> LazyHTML.to_tree() != []
  end
end
