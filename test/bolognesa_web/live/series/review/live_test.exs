defmodule BolognesaWeb.Series.Review.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Identification.Infrastructure.Repositories.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Test.DelayedSearchSeriesProvider
  alias Bolognesa.Test.SyntheticSeriesProvider
  alias BolognesaWeb.SeriesFixtures

  setup %{conn: conn} do
    ctx = SeriesFixtures.setup(conn)
    old = Application.get_env(:bolognesa, :series_provider_adapter)
    Application.put_env(:bolognesa, :series_provider_adapter, SyntheticSeriesProvider)

    on_exit(fn ->
      if old,
        do: Application.put_env(:bolognesa, :series_provider_adapter, old),
        else: Application.delete_env(:bolognesa, :series_provider_adapter)

      File.rm_rf!(ctx.directory)
    end)

    ctx
  end

  test "searches a series selects a season and corrects the whole set", ctx do
    {:ok, view, _} = live(ctx.conn, "/series/review?file_id=#{ctx.media_file.id}")
    render_async(view)
    view |> form("#series-search", search: %{query: "Serie"}) |> render_submit()
    render_async(view)
    view |> element("#series-candidate-201") |> render_click()
    view |> form("#series-season-form", season: %{number: "0"}) |> render_submit()
    render_async(view)

    view
    |> form("#series-correction-form", selection: %{episode_numbers: ["2"]})
    |> render_submit()

    render_async(view)
    assert has_element?(view, "#series-review-feedback", "guardada")
    assert {:ok, %{catalog_entry_ids: [id]}} = Repository.get(ctx.media_file.id)
    assert id == List.last(ctx.episode_ids)
    render_submit(view, "correct", %{"selection" => %{"episode_numbers" => [""]}})
    assert has_element?(view, "#series-review-feedback", "Selecciona")
  end

  test "invalid retry id gives feedback", ctx do
    {:ok, view, _} = live(ctx.conn, "/series/review")
    render_async(view)
    render_click(view, "retry", %{"file_id" => "bad"})
    assert has_element?(view, "#series-review-feedback", "No se pudo")
  end

  test "a new search cancels the unfinished previous search", ctx do
    Application.put_env(:bolognesa, :series_search_test_owner, self())
    Application.put_env(:bolognesa, :series_provider_adapter, DelayedSearchSeriesProvider)
    on_exit(fn -> Application.delete_env(:bolognesa, :series_search_test_owner) end)
    {:ok, view, _} = live(ctx.conn, "/series/review?file_id=#{ctx.media_file.id}")
    render_async(view)
    view |> form("#series-search", search: %{query: "Slow"}) |> render_submit()
    assert_receive {:search_started, pid}
    monitor = Process.monitor(pid)
    view |> form("#series-search", search: %{query: "Sin coincidencia"}) |> render_submit()
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}
    render_async(view)
    assert has_element?(view, "#series-review-feedback", "No se encontraron")
    refute has_element?(view, "#series-candidate-201")
  end
end
