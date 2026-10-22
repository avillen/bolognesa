defmodule Bolognesa.Infrastructure.PromExTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Infrastructure.Observability.PromEx, as: Metrics

  @token String.duplicate("test-only-", 8)

  setup do
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

  defp enable_metrics do
    Application.put_env(:bolognesa, Metrics,
      disabled: false,
      manual_metrics_start_delay: :no_delay
    )

    Application.put_env(:bolognesa, :metrics_token, @token)
    start_supervised!(Metrics)
  end
end
