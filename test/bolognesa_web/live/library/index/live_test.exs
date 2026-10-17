defmodule BolognesaWeb.Library.Index.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  alias Bolognesa.Libraries.Application.UseCases.ReconcileInspections
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  alias BolognesaWeb.Library.Index.Live
  alias BolognesaWeb.Library.Index.Reducers.Initialize
  alias Phoenix.LiveView.Channel
  import Phoenix.LiveViewTest

  alias Bolognesa.Accounts
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Application.UseCases.InspectMediaFile
  alias Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker

  alias Bolognesa.Libraries.Infrastructure.Repositories.{
    EctoInspectionRepository,
    EctoOutboxRepository,
    EctoScanRepository
  }

  alias Bolognesa.Libraries.Support.SuccessfulMediaProbe
  alias Bolognesa.Repo
  use Oban.Testing, repo: Bolognesa.Repo

  setup do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "ada@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Accounts.start_session("ada@example.com", "correct horse battery staple")
    root = Application.fetch_env!(:bolognesa, :library_roots) |> hd()
    path = Path.join(root, "web-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    {:ok, actor} = Accounts.fetch_authenticated_user(token)
    %{token: token, path: path, actor: actor}
  end

  test "creates a music library and updates its navigation immediately", %{
    conn: conn,
    token: token,
    path: path
  } do
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")

    view
    |> form("#library-form", library: %{name: "Music", path: path, content_type: "music"})
    |> render_submit()

    assert has_element?(view, "#library-list [data-content-type='music']")
    assert has_element?(view, "nav a[id^=nav-library-] .hero-musical-note")
    assert has_element?(view, "nav a[href^='/music?library_id=']", "Music")
  end

  test "creates a series library and rejects an unknown form type", %{
    conn: conn,
    token: token,
    path: path
  } do
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")

    render_submit(view, "save", %{
      "library" => %{"name" => "Series", "path" => path, "content_type" => "mixed"}
    })

    refute has_element?(view, "#library-list [data-library-name='Series']")

    view
    |> form("#library-form", library: %{name: "Series", path: path, content_type: "series"})
    |> render_submit()

    assert has_element?(view, "#library-list [data-library-name='Series']", "Series")
    assert has_element?(view, "nav a[id^=nav-library-] .hero-tv")
    assert has_element?(view, "nav a[id^=nav-library-]", "Series")
    {:ok, reopened, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    assert has_element?(reopened, "#library-list [data-content-type='series']")
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

    {:ok, new_token} = Accounts.start_session("ada@example.com", "correct horse battery staple")
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
    {:ok, library} =
      Libraries.create_library(actor, %{name: "Scan", path: path, content_type: :movie})

    conn = init_test_session(conn, user_token: token)
    {:ok, view, _} = live(conn, ~p"/libraries")
    await_status_updates(view)
    view |> element("#library-scan-#{library.id}") |> render_click()
    assert has_element?(view, "#library-scan-#{library.id}[disabled]")
    assert has_element?(view, "#library-scan-state-#{library.id}[data-state='queued']")
    assert {:ok, %{latest_scan: scan}} = Libraries.fetch_scan_status(actor, library.id)
    assert_enqueued(worker: ScanWorker, args: %{scan_id: scan.id})
    {:ok, reopened, _} = live(conn, ~p"/libraries")
    await_status_updates(reopened)
    assert has_element?(reopened, "#library-scan-state-#{library.id}[data-state='queued']")
  end

  test "manual drain updates discovery through notifications", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    File.write!(Path.join(path, "movie.MKV"), "video")

    {:ok, library} =
      Libraries.create_library(actor, %{name: "Complete", path: path, content_type: :movie})

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    await_status_updates(view)
    view |> element("#library-scan-#{library.id}") |> render_click()
    await_status_updates(view)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)
    render(view)
    await_status_updates(view)
    assert has_element?(view, "#library-scan-state-#{library.id}[data-state='completed']")
    assert has_element?(view, "#library-scan-count-#{library.id}", "1 archivo")
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

    {:ok, library} =
      Libraries.create_library(actor, %{name: "Technical", path: path, content_type: :movie})

    {:ok, first_scan} = Libraries.start_scan(actor, library.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    await_status_updates(view)
    assert has_element?(view, "#library-inspection-counts-#{library.id}[data-pending='1']")
    view |> element("#library-reinspect-#{library.id}") |> render_click()
    assert has_element?(view, "#library-reinspect-confirm-#{library.id}")
    view |> element("#library-reinspect-confirm-button-#{library.id}") |> render_click()
    assert has_element?(view, "#library-scan-state-#{library.id}[data-state='queued']")
    assert has_element?(view, "#library-reinspect-#{library.id}[disabled]")
    assert {:ok, %{latest_scan: forced}} = Libraries.fetch_scan_status(actor, library.id)
    assert forced.id != first_scan.id
    assert forced.force_inspection?

    {:ok, reopened, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    await_status_updates(reopened)
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

    {:ok, library} =
      Libraries.create_library(actor, %{name: "Broken", path: path, content_type: :movie})

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
    await_status_updates(view)

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
    await_status_updates(reopened)
    assert has_element?(reopened, "#library-inspection-counts-#{library.id}[data-failed='3']")
    assert has_element?(reopened, "#library-inspection-failure-#{library.id}-invalid_output")
    assert has_element?(reopened, "#library-inspection-failure-#{library.id}-source_changed")
  end

  @tag capture_log: true
  test "incomplete scan explains that discovered files can still be analysed", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    alias Bolognesa.Infrastructure.Persistence.ScanSchema

    File.write!(Path.join(path, "episode.mkv"), "video")

    {:ok, library} =
      Libraries.create_library(actor, %{name: "Incomplete", path: path, content_type: :series})

    {:ok, scan} = Libraries.start_scan(actor, library.id)
    assert %{success: 1} = Oban.drain_queue(queue: :library_scans)

    Repo.get!(ScanSchema, scan.id)
    |> ScanSchema.changeset(%{state: :failed, failure_reason: :entry_unreadable})
    |> Repo.update!()

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    await_status_updates(view)
    selector = "#library-scan-error-#{library.id}"
    assert has_element?(view, selector, "Inventario incompleto")
    assert has_element?(view, selector, "1 archivo registrado antes del fallo")
    assert has_element?(view, selector, "Comprueba los permisos de lectura")
    assert has_element?(view, selector, "El análisis de los archivos ya registrados continúa")

    Repo.update_all(InspectionSchema, set: [state: :succeeded])
    send(view.pid, {:library_status_changed, library.id})
    render(view)
    await_status_updates(view)
    refute has_element?(view, selector, "El análisis de los archivos ya registrados continúa")
    assert has_element?(view, selector, "Inventario incompleto")
  end

  @tag capture_log: true
  test "failed scan can be retried and leaving the page does not cancel its job", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    {:ok, library} =
      Libraries.create_library(actor, %{name: "Retry", path: path, content_type: :movie})

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    await_status_updates(view)
    view |> element("#library-scan-#{library.id}") |> render_click()
    await_status_updates(view)
    File.rmdir!(path)
    assert %{cancelled: 1} = Oban.drain_queue(queue: :library_scans)
    render(view)
    await_status_updates(view)
    assert has_element?(view, "#library-scan-error-#{library.id}")
    assert has_element?(view, "#library-scan-#{library.id}", "Reintentar")
    File.mkdir_p!(path)
    view |> element("#library-scan-#{library.id}") |> render_click()

    assert {:ok, %{latest_scan: %{state: :queued} = scan}} =
             Libraries.fetch_scan_status(actor, library.id)

    await_status_updates(view)
    ref = Process.monitor(view.pid)
    GenServer.stop(view.pid)
    assert_receive {:DOWN, ^ref, :process, _, _}
    assert_enqueued(worker: ScanWorker, args: %{scan_id: scan.id})
  end

  test "a scan requested in another tab updates an already open library screen", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    {:ok, library} =
      Libraries.create_library(actor, %{name: "Shared", path: path, content_type: :movie})

    conn = init_test_session(conn, user_token: token)
    {:ok, first, _} = live(conn, ~p"/libraries")
    {:ok, second, _} = live(conn, ~p"/libraries")
    await_status_updates(first)
    await_status_updates(second)

    first |> element("#library-scan-#{library.id}") |> render_click()
    await_status_updates(first)
    render(second)
    await_status_updates(second)
    assert has_element?(second, "#library-scan-state-#{library.id}[data-state='queued']")
    assert has_element?(second, "#library-scan-#{library.id}[disabled]")
  end

  test "inspection completion updates counts after the scan has finished", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    File.write!(Path.join(path, "movie.mkv"), "video")

    {:ok, library} =
      Libraries.create_library(actor, %{name: "Inspected", path: path, content_type: :movie})

    {:ok, _} = Libraries.start_scan(actor, library.id)
    assert %{success: 1} = Oban.drain_queue(queue: :library_scans)
    inspection = Repo.one!(InspectionSchema)

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    await_status_updates(view)
    assert has_element?(view, "#library-inspection-counts-#{library.id}[data-pending='1']")

    assert :ok =
             InspectMediaFile.call(
               inspection.media_file_id,
               inspection.token,
               1,
               EctoInspectionRepository,
               SuccessfulMediaProbe,
               LibraryStatusNotifications
             )

    render(view)
    await_status_updates(view)

    assert has_element?(
             view,
             "#library-inspection-counts-#{library.id}[data-succeeded='1'][data-pending='0']"
           )

    refute has_element?(view, "#library-reinspect-#{library.id}[disabled]")
  end

  test "inspection recovery updates failure feedback after the scan has finished", %{
    conn: conn,
    token: token,
    path: path,
    actor: actor
  } do
    File.write!(Path.join(path, "movie.mkv"), "video")

    {:ok, library} =
      Libraries.create_library(actor, %{name: "Recovered", path: path, content_type: :movie})

    {:ok, _} = Libraries.start_scan(actor, library.id)
    assert %{success: 1} = Oban.drain_queue(queue: :library_scans)
    assert {:ok, 1} = EctoOutboxRepository.dispatch_batch(25)
    inspection = Repo.one!(InspectionSchema)
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    await_status_updates(view)

    Repo.get!(Oban.Job, inspection.job_id)
    |> Ecto.Changeset.change(state: "discarded")
    |> Repo.update!()

    assert :ok =
             ReconcileInspections.call(
               DateTime.utc_now(),
               EctoInspectionRepository,
               LibraryStatusNotifications
             )

    render(view)
    await_status_updates(view)
    assert has_element?(view, "#library-inspection-counts-#{library.id}[data-failed='1']")
    assert has_element?(view, "#library-inspection-failure-#{library.id}-attempts_exhausted")
  end

  test "hints received during a status read cause a following read of completion", %{
    path: path,
    actor: actor
  } do
    alias BolognesaWeb.Library.Index.Reducers.ApplyScanStatuses

    {:ok, library} =
      Libraries.create_library(actor, %{name: "Current", path: path, content_type: :movie})

    {:ok, scan} = Libraries.start_scan(actor, library.id)
    {:ok, old_status} = Libraries.fetch_scan_status(actor, library.id)
    {:ok, counts} = Libraries.fetch_inspection_counts(actor, library.id)
    socket = status_socket(actor)
    socket = %{socket | transport_pid: self()}
    socket = Phoenix.Component.assign(socket, :scan_loading?, true)
    old_request = socket.assigns.scan_request_id
    {:noreply, socket} = Live.handle_info({:library_status_changed, library.id}, socket)
    {:noreply, socket} = Live.handle_info({:library_status_changed, library.id}, socket)
    assert socket.assigns.scan_refresh_pending?
    socket = ApplyScanStatuses.call(socket, make_ref(), {:ok, {:ok, []}})
    assert socket.assigns.scan_refresh_pending?
    assert socket.assigns.scan_loading?

    {:ok, running, _} = EctoScanRepository.begin_attempt(scan.id, 1)
    {:ok, _} = EctoScanRepository.complete(scan.id, running.generation)

    socket =
      ApplyScanStatuses.call(socket, old_request, {:ok, {:ok, [{library, old_status, counts}]}})

    new_request = socket.assigns.scan_request_id
    refute new_request == old_request
    assert socket.assigns.scan_loading?
    refute socket.assigns.scan_refresh_pending?

    assert_receive {:phoenix, :async_result,
                    {:start, {_ref, nil, {:scan_statuses, ^new_request}, result}}}

    {:noreply, socket} = Live.handle_async({:scan_statuses, new_request}, result, socket)
    refute socket.assigns.scan_loading?
    html = render_component(&Live.render/1, Map.put(socket.assigns, :__changed__, nil))

    assert LazyHTML.query(
             LazyHTML.from_fragment(html),
             "#library-scan-state-#{library.id}[data-state='completed']"
           )
           |> LazyHTML.to_tree() != []
  end

  test "a failed refresh consumes a pending hint without retrying indefinitely", %{actor: actor} do
    alias BolognesaWeb.Library.Index.Reducers.ApplyScanStatuses
    socket = status_socket(actor)
    socket = %{socket | transport_pid: self()}
    socket = Phoenix.Component.assign(socket, :current_scope, %{actor: nil})
    socket = Phoenix.Component.assign(socket, :scan_loading?, true)
    request = socket.assigns.scan_request_id
    {:noreply, socket} = Live.handle_info({:library_status_changed, 1}, socket)
    socket = ApplyScanStatuses.call(socket, request, {:ok, {:error, :unavailable}})
    retry_request = socket.assigns.scan_request_id
    refute retry_request == request

    assert_receive {:phoenix, :async_result,
                    {:start, {_ref, nil, {:scan_statuses, ^retry_request}, result}}}

    {:noreply, socket} = Live.handle_async({:scan_statuses, retry_request}, result, socket)
    refute socket.assigns.scan_loading?
    refute socket.assigns.scan_refresh_pending?
    assert socket.assigns.scan_feedback
    assert socket.assigns.scan_request_id == retry_request
  end

  test "invalid and missing library clicks produce feedback without a job", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/libraries")
    await_status_updates(view)

    for id <- ["0", "-1", "1oops", "999999999"] do
      render_click(view, "scan", %{"library_id" => id})
      assert has_element?(view, "#library-scan-feedback")
      await_status_updates(view)
    end

    refute_enqueued(worker: ScanWorker)
  end

  test "stale status replies and update failures preserve rendered rows", %{
    path: path,
    actor: actor
  } do
    alias BolognesaWeb.Library.Index.Reducers.{ApplyScanStatuses, Initialize}
    alias Live

    {:ok, library} =
      Libraries.create_library(actor, %{name: "Retained", path: path, content_type: :movie})

    {:ok, _scan} = Libraries.start_scan(actor, library.id)
    {:ok, status} = Libraries.fetch_scan_status(actor, library.id)
    {:ok, counts} = Libraries.fetch_inspection_counts(actor, library.id)

    socket =
      %Phoenix.LiveView.Socket{
        endpoint: BolognesaWeb.Endpoint,
        private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}},
        assigns: %{__changed__: %{}, flash: %{}}
      }
      |> Phoenix.Component.assign(:current_scope, %{actor: actor})
      |> with_navigation()
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

    assert {:ok, %{latest_scan: %{state: :queued}}} =
             Libraries.fetch_scan_status(actor, library.id)
  end

  test "scan reducer delegates authorization and creates no unauthorized job", %{
    path: path,
    actor: actor
  } do
    alias BolognesaWeb.Library.Index.Reducers.{Initialize, StartScan}

    {:ok, library} =
      Libraries.create_library(actor, %{name: "Authorized", path: path, content_type: :movie})

    socket =
      %Phoenix.LiveView.Socket{
        endpoint: BolognesaWeb.Endpoint,
        private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}},
        assigns: %{__changed__: %{}, flash: %{}}
      }
      |> Phoenix.Component.assign(:current_scope, %{actor: actor})
      |> with_navigation()
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
      |> with_navigation()
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

  # render_async/1 waits for a snapshot; an incoming hint can start a following read.
  defp await_status_updates(view) do
    html = Phoenix.LiveViewTest.render_async(view)

    case Channel.async_pids(view.pid) do
      {:ok, []} -> html
      {:ok, [_ | _]} -> await_status_updates(view)
    end
  end

  defp status_socket(actor) do
    %Phoenix.LiveView.Socket{
      endpoint: BolognesaWeb.Endpoint,
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}},
      assigns: %{__changed__: %{}, flash: %{}}
    }
    |> Phoenix.Component.assign(:current_scope, %{actor: actor})
    |> with_navigation()
    |> Initialize.call()
  end

  defp with_navigation(socket) do
    {:cont, socket} =
      BolognesaWeb.LibraryNavigation.on_mount(:default, %{}, %{}, %{
        socket
        | router: BolognesaWeb.Router
      })

    socket
  end
end
