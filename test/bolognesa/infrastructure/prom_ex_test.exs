defmodule Bolognesa.Infrastructure.PromExTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Ecto.Adapters.SQL.Sandbox

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Infrastructure.Observability.PromEx, as: Metrics

  @token String.duplicate("test-only-", 8)

  setup do
    owner = Sandbox.start_owner!(Bolognesa.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    previous_exporter = Application.get_env(:bolognesa, Metrics)
    previous_token = Application.get_env(:bolognesa, :metrics_token)

    on_exit(fn ->
      Application.put_env(:bolognesa, Metrics, previous_exporter)
      Application.put_env(:bolognesa, :metrics_token, previous_token)
    end)

    :ok
  end

  test "normal startup disables the exporter and its HTTP endpoint" do
    assert Application.fetch_env!(:bolognesa, Metrics)[:disabled]
    assert Metrics.start_link([]) == :ignore

    conn = BolognesaWeb.Endpoint.call(conn(:get, "/metrics"), [])
    assert conn.status == 404
    refute conn.resp_body =~ "# TYPE"
  end

  test "enabled metrics require the exact bearer credential" do
    enable_metrics()

    for headers <- [[], ["Bearer wrong"], ["Bearer " <> @token, "Bearer " <> @token]] do
      conn = conn(:get, "/metrics")
      conn = %{conn | req_headers: Enum.map(headers, &{"authorization", &1})}
      response = BolognesaWeb.Endpoint.call(conn, [])
      assert response.status == 401
      refute response.resp_body =~ "# TYPE"
    end
  end

  test "authorized scraping exports real observations without private identifiers" do
    enable_metrics()

    Events.emit(
      :libraries,
      :scan,
      :completed,
      %{library_id: 987_654, scan_id: 123_456, reason: :unavailable},
      %{duration_ms: 42, files_discovered: 2}
    )

    :telemetry.execute(
      [:bolognesa, :playback, :session, :closed],
      %{count: 1, duration_ms: 42},
      %{session_id: "private-session", reason: :ended}
    )

    private_conn = conn("PRIVATE_METHOD", "/private-media-title?token=private-query-token")
    private_conn = %{private_conn | host: "private-host.invalid", status: 404}

    :telemetry.execute([:phoenix, :endpoint, :stop], %{duration: 1_000}, %{conn: private_conn})

    :telemetry.execute(
      [:bolognesa, :unregistered, :private, :completed],
      %{count: 1},
      %{file_id: "private-file-id"}
    )

    response =
      conn(:get, "/metrics")
      |> put_req_header("authorization", "Bearer " <> @token)
      |> BolognesaWeb.Endpoint.call([])

    assert response.status == 200
    assert response.resp_body =~ "bolognesa_libraries_scan_completed_count"
    assert response.resp_body =~ "bolognesa_libraries_scan_completed_duration_milliseconds_bucket"
    assert response.resp_body =~ "bolognesa_playback_session_closed_count"
    assert response.resp_body =~ "bolognesa_playback_session_closed_duration_milliseconds_bucket"
    refute response.resp_body =~ "private-session"
    assert response.resp_body =~ "bolognesa_prom_ex_beam"
    refute response.resp_body =~ "987654"
    refute response.resp_body =~ "123456"
    refute response.resp_body =~ @token
    refute response.resp_body =~ "library_id="
    refute response.resp_body =~ "scan_id="
    refute response.resp_body =~ "private-media-title"
    refute response.resp_body =~ "private-query-token"
    refute response.resp_body =~ "private-host.invalid"
    refute response.resp_body =~ "PRIVATE_METHOD"
    refute response.resp_body =~ "unregistered"
    assert response.resp_body =~ ~s(method="OTHER")
  end

  test "LiveView callbacks export bounded ownership and durations without browser metadata" do
    enable_metrics()

    for {view, context} <- [
          {BolognesaWeb.Movie.Index.Live, "movies"},
          {BolognesaWeb.Episode.Show.Live, "series"},
          {Phoenix.LiveDashboard.PageLive, "global"}
        ],
        operation <- [:mount, :handle_params, :handle_event, :render] do
      metadata = %{
        socket: %Phoenix.LiveView.Socket{view: view},
        session: %{},
        uri: "https://example.invalid/private-browser-uri",
        event: "private-browser-event",
        params: %{token: "private-browser-token"},
        reason: "private-exception-message"
      }

      :telemetry.execute(
        [:phoenix, :live_view, operation, :stop],
        %{duration: System.convert_time_unit(2, :millisecond, :native)},
        metadata
      )

      :telemetry.execute(
        [:phoenix, :live_view, operation, :exception],
        %{duration: System.convert_time_unit(3, :millisecond, :native)},
        metadata
      )

      export = PromEx.get_metrics(Metrics)

      assert export =~
               "bolognesa_prom_ex_phoenix_live_view_#{operation}_duration_milliseconds_bucket"

      assert export =~
               "bolognesa_prom_ex_phoenix_live_view_#{operation}_exception_duration_milliseconds_count"

      assert export =~ ~s(context="#{context}")
      refute export =~ "private-browser"
      refute export =~ "private-exception"
      refute export =~ "PageLive"
    end
  end

  test "playback diagnostics distinguish buffer waits and failed FFmpeg exits with bounded labels" do
    enable_metrics()

    ExUnit.CaptureLog.capture_log(fn ->
      for diagnostic <- [:waiting, :recovered, :error, "private-diagnostic"] do
        :telemetry.execute([:bolognesa, :playback, :browser, :diagnostic], %{count: 1}, %{
          diagnostic: diagnostic,
          file_id: 123_456,
          tab_id: "private-tab"
        })
      end

      :telemetry.execute([:bolognesa, :playback, :session, :exited], %{count: 1}, %{
        reason: :failed,
        session_id: "private-session"
      })
    end)

    export = PromEx.get_metrics(Metrics)
    assert export =~ ~s(bolognesa_playback_browser_observations_total{diagnostic="waiting"} 1)
    assert export =~ ~s(bolognesa_playback_browser_observations_total{diagnostic="recovered"} 1)
    assert export =~ ~s(bolognesa_playback_ffmpeg_exits_total{result="failed"} 1)
    refute export =~ "private-diagnostic"
    refute export =~ "private-tab"
    refute export =~ "private-session"
  end

  test "Ecto exports precise small-query buckets without SQL or parameters" do
    enable_metrics()

    :telemetry.execute(
      [:bolognesa, :repo, :query],
      %{
        query_time: System.convert_time_unit(2, :millisecond, :native),
        total_time: System.convert_time_unit(3, :millisecond, :native),
        queue_time: 0,
        decode_time: 0,
        idle_time: 0
      },
      %{
        repo: Bolognesa.Repo,
        source: "accounts_users",
        result: {:ok, %Postgrex.Result{command: :select, num_rows: 1}},
        query: "private-sql",
        params: ["private-parameter"]
      }
    )

    :telemetry.execute([:bolognesa, :repo, :query], %{query_time: 0, total_time: 0}, %{
      repo: Bolognesa.Repo,
      source: "accounts_users",
      result: {:error, RuntimeError.exception("private-database-error")},
      query: "private-failed-sql",
      params: ["private-parameter"]
    })

    export = PromEx.get_metrics(Metrics)
    assert export =~ ~s(source="accounts_users")
    assert export =~ ~s(le="0.1")
    assert export =~ ~s(le="2.5")
    assert export =~ "bolognesa_prom_ex_ecto_repo_query_execution_time_milliseconds_sum"

    assert export =~
             ~s(bolognesa_prom_ex_ecto_repo_query_errors_total{repo="Bolognesa.Repo",source="accounts_users"} 1)

    refute export =~ "private-database-error"
    refute export =~ "private-failed-sql"
    refute export =~ "private-sql"
    refute export =~ "private-parameter"
  end

  defp enable_metrics do
    Application.put_env(:bolognesa, Metrics,
      disabled: false,
      manual_metrics_start_delay: :no_delay
    )

    Application.put_env(:bolognesa, :metrics_token, @token)
    start_supervised!(Metrics)
  end
end
