defmodule BolognesaWeb.MediaDeliveryObservationAdapter do
  @moduledoc false
  alias Plug.Adapters.Test.Conn, as: TestConn

  @spec send_chunked(map(), non_neg_integer(), list()) :: {:ok, binary(), map()}
  def send_chunked(state, status, headers) do
    if state.mode == :truncate, do: File.write!(state.path, "")
    TestConn.send_chunked(state, status, headers)
  end

  @spec chunk(map(), iodata()) :: {:error, :closed | map()} | {:ok, binary(), map()}
  def chunk(%{mode: :closed}, _body), do: {:error, :closed}

  def chunk(%{mode: :transport_fault}, _body),
    do: {:error, %{exception: "secret /private media path"}}

  def chunk(state, body), do: TestConn.chunk(state, body)

  @spec send_resp(map(), non_neg_integer(), list(), iodata()) :: {:ok, binary(), map()}
  def send_resp(state, status, headers, body),
    do: TestConn.send_resp(state, status, headers, body)
end

defmodule BolognesaWeb.MediaDeliveryObservabilityTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias BolognesaWeb.MediaDelivery
  alias BolognesaWeb.MediaDeliveryObservationAdapter

  setup do
    base = hd(Application.fetch_env!(:bolognesa, :library_roots))
    directory = Path.join(base, "bolognesa-delivery-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    {:ok, directory} = LocalSourcePath.canonical_directory(directory)
    path = Path.join(directory, "private-media.mp4")
    File.write!(path, "abcdefgh")
    stat = File.stat!(path, time: :posix)

    source = %Source{
      path: directory,
      relative_path: "private-media.mp4",
      size_bytes: 8,
      modified_at: DateTime.from_unix!(stat.mtime)
    }

    on_exit(fn -> File.rm_rf!(directory) end)

    id = {__MODULE__, make_ref()}
    event = [:bolognesa, :playback, :delivery, :failed]
    :telemetry.attach(id, event, &__MODULE__.capture/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    %{source: source, path: path, event: event}
  end

  @spec capture([atom()], map(), map(), pid()) :: :ok
  def capture(event, measurements, metadata, receiver) do
    if self() == receiver, do: send(receiver, {event, measurements, metadata})
    :ok
  end

  test "range failures emit one observation and successful delivery remains quiet", %{
    source: source,
    event: event
  } do
    conn = Plug.Test.conn(:get, "/") |> MediaDelivery.with_resource(:movie, "42")
    assert MediaDelivery.serve(conn, source, "video/mp4").status == 200
    refute_receive {^event, _, _}

    conn = Plug.Test.conn(:get, "/") |> MediaDelivery.with_resource(:music, "43")
    conn = put_req_header(conn, "range", "bytes=secret")
    assert MediaDelivery.serve(conn, source, "audio/mpeg").status == 400

    assert_receive {^event, %{count: 1},
                    %{
                      file_id: 43,
                      resource_type: :music,
                      failure_stage: :range,
                      reason: :invalid_range,
                      status: 400
                    }}

    refute_receive {^event, _, _}
  end

  test "source validation failure contains IDs and no private source", %{
    source: source,
    path: path,
    event: event
  } do
    File.rm!(path)
    conn = Plug.Test.conn(:get, "/") |> MediaDelivery.with_resource(:episode, "44")
    assert MediaDelivery.serve(conn, source, "video/mp4").status == 404
    assert_receive {^event, %{count: 1}, metadata}

    assert metadata == %{
             file_id: 44,
             resource_type: :episode,
             failure_stage: :source_validation,
             reason: :unreadable,
             status: 404
           }

    refute inspect(metadata) =~ "private"
    refute_receive {^event, _, _}
  end

  test "truncation and closed connections after headers keep their original HTTP status", %{
    source: source,
    path: path,
    event: event
  } do
    for {mode, stage, reason} <- [
          {:truncate, :read, :read_failed},
          {:closed, :chunk, :client_closed},
          {:transport_fault, :chunk, :send_failed}
        ] do
      File.write!(path, "abcdefgh")
      source = %{source | modified_at: DateTime.from_unix!(File.stat!(path, time: :posix).mtime)}
      conn = Plug.Test.conn(:get, "/") |> MediaDelivery.with_resource(:music, 45)
      {_, state} = conn.adapter

      conn = %{
        conn
        | adapter: {MediaDeliveryObservationAdapter, Map.merge(state, %{mode: mode, path: path})}
      }

      delivered = MediaDelivery.serve(conn, source, "audio/mpeg")
      assert delivered.status == 200
      assert delivered.state == :chunked

      assert_receive {^event, %{count: 1},
                      %{
                        file_id: 45,
                        resource_type: :music,
                        failure_stage: ^stage,
                        reason: ^reason,
                        status: 200
                      }}

      refute_receive {^event, _, _}
    end
  end

  test "invalid resource identifiers are excluded before telemetry", %{event: event} do
    conn = Plug.Test.conn(:get, "/") |> MediaDelivery.with_resource(:movie, "private@example.com")
    assert MediaDelivery.error_response(conn, :not_found).status == 404
    assert_receive {^event, %{count: 1}, metadata}

    assert metadata == %{
             resource_type: :movie,
             failure_stage: :selection,
             reason: :not_found,
             status: 404
           }

    assert :ok ==
             Events.emit(:playback, :delivery, :failed, %{file_id: "secret", reason: "secret"})

    assert_receive {^event, %{count: 1}, %{}}
  end
end
