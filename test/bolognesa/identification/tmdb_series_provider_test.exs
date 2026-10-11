defmodule Bolognesa.Identification.TmdbSeriesProviderTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Identification.Infrastructure.Providers.TmdbSeriesProvider

  test "search sends initial year and limits safe candidates" do
    parent = self()

    plug = fn conn ->
      send(parent, {:request, conn.request_path, URI.decode_query(conn.query_string)})

      results =
        for id <- 1..8, do: %{id: id, name: "Serie", first_air_date: "2001-01-01", adult: false}

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{results: results ++ [%{id: 99, name: "Adult", adult: true}]})
      )
    end

    assert {:ok, candidates} = TmdbSeriesProvider.search("Serie", 2001, token: "test", plug: plug)
    assert length(candidates) == 5
    assert hd(candidates).year == 2001
    assert_receive {:request, "/3/search/tv", query}
    assert query["first_air_date_year"] == "2001"
    refute Map.has_key?(query, "year")
    assert query["language"] == "es-ES"
  end

  test "details verify ID and sanitize images with absent optional metadata" do
    plug = json(%{id: 201, name: "Serie", poster_path: "https://unsafe.example/image"})
    assert {:ok, details} = TmdbSeriesProvider.details(201, token: "test", plug: plug)
    assert details.poster_path == nil
    assert details.year == nil

    assert {:error, :invalid_response} =
             TmdbSeriesProvider.details(202, token: "test", plug: plug)
  end

  test "season zero normalizes every episode and validates numbers" do
    parent = self()

    body = %{
      id: 301,
      season_number: 0,
      episodes: [
        %{id: 401, season_number: 0, episode_number: 1, name: "Uno", air_date: nil},
        %{id: 402, season_number: 0, episode_number: 2, name: "Dos", air_date: "2001-01-02"}
      ]
    }

    plug = fn conn ->
      send(parent, {:season_path, conn.request_path})
      Plug.Conn.resp(conn, 200, Jason.encode!(body))
    end

    assert {:ok, season} = TmdbSeriesProvider.season(201, 0, token: "test", plug: plug)
    assert season.series_provider_id == 201
    assert Enum.map(season.episodes, & &1.number) == [1, 2]
    assert List.last(season.episodes).air_date == ~D[2001-01-02]
    assert_receive {:season_path, "/3/tv/201/season/0"}

    assert {:error, :invalid_response} =
             TmdbSeriesProvider.season(201, 1, token: "test", plug: json(body))

    for episodes <- [
          body.episodes ++ body.episodes,
          [%{id: 401, season_number: 0, episode_number: 0, name: "Zero"}],
          ["bad"]
        ] do
      assert {:error, :invalid_response} =
               TmdbSeriesProvider.season(201, 0,
                 token: "test",
                 plug: json(%{body | episodes: episodes})
               )
    end
  end

  test "normalizes empty search configuration HTTP transport and body failures" do
    assert {:ok, []} =
             TmdbSeriesProvider.search("Serie", nil, token: "test", plug: json(%{results: []}))

    assert {:error, :not_configured} = TmdbSeriesProvider.search("Serie", nil, token: nil)

    for {status, reason} <- [
          {401, :unauthorized},
          {403, :unauthorized},
          {404, :not_found},
          {429, :rate_limited},
          {500, :provider_unavailable}
        ] do
      plug = fn conn -> Plug.Conn.resp(conn, status, "private-body") end

      assert {:error, ^reason} =
               TmdbSeriesProvider.search("Serie", nil, token: "test", plug: plug)
    end

    for body <- ["broken", String.duplicate("x", 1_048_577)] do
      plug = fn conn -> Plug.Conn.resp(conn, 200, body) end

      assert {:error, :invalid_response} =
               TmdbSeriesProvider.search("Serie", nil, token: "test", plug: plug)
    end

    plug = fn _ -> raise "synthetic transport failure" end

    assert {:error, :provider_unavailable} =
             TmdbSeriesProvider.search("Serie", nil, token: "test", plug: plug)
  end

  defp json(body), do: fn conn -> Plug.Conn.resp(conn, 200, Jason.encode!(body)) end
end
