defmodule Bolognesa.Movies.TmdbMovieProviderTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Movies.Infrastructure.Providers.TmdbMovieProvider

  test "search sends only inferred title and returns bounded non-adult candidates" do
    parent = self()

    plug = fn conn ->
      send(parent, {:request, conn.request_path, conn.query_string, conn.req_headers})

      body =
        Jason.encode!(%{
          page: 1,
          total_pages: 1,
          total_results: 3,
          results: [
            %{
              id: 42,
              title: "Mi película",
              original_title: "My Movie",
              release_date: "2001-01-01",
              adult: false,
              poster_path: "/poster.jpg"
            },
            %{
              id: 43,
              title: "Adulto",
              original_title: "Adult",
              release_date: "2001-01-01",
              adult: true
            },
            %{id: -1, title: "Inválida", adult: false}
          ]
        })

      Plug.Conn.resp(conn, 200, body)
    end

    assert {:ok, [candidate]} =
             TmdbMovieProvider.search("Mi película", 2001, token: "test-token", plug: plug)

    assert candidate.provider_id == 42
    assert candidate.poster_path == "/poster.jpg"
    assert_receive {:request, "/3/search/movie", query, headers}
    assert URI.decode_query(query)["query"] == "Mi película"
    assert URI.decode_query(query)["language"] == "es-ES"
    assert URI.decode_query(query)["include_adult"] == "false"
    refute query =~ "privado"
    assert {"authorization", "Bearer test-token"} in headers
  end

  test "details accept absent optional values and reject unsafe image paths" do
    plug = fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          id: 42,
          title: "Película",
          overview: nil,
          poster_path: "https://bad.example/image.jpg"
        })
      )
    end

    assert {:ok, details} = TmdbMovieProvider.details(42, token: "test-token", plug: plug)
    assert details.provider_id == 42
    assert details.overview == nil
    assert details.poster_path == nil
  end

  test "ignores malformed search items while keeping the first valid result" do
    plug = fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{results: ["unexpected", %{id: 42, title: "Película", adult: false}]})
      )
    end

    assert {:ok, [%{provider_id: 42}]} =
             TmdbMovieProvider.search("Película", nil, token: "test-token", plug: plug)
  end

  test "rejects details for a different provider ID" do
    plug = fn conn -> Plug.Conn.resp(conn, 200, Jason.encode!(%{id: 43, title: "Otra"})) end

    assert {:error, :invalid_response} =
             TmdbMovieProvider.details(42, token: "test-token", plug: plug)
  end

  test "returns safe reasons for absent token and provider failures" do
    assert {:error, :not_configured} = TmdbMovieProvider.search("Film", nil, token: nil)
    assert {:error, :not_configured} = TmdbMovieProvider.search("Film", nil)

    for {status, reason} <- [
          {401, :unauthorized},
          {429, :rate_limited},
          {503, :provider_unavailable}
        ] do
      plug = fn conn -> Plug.Conn.resp(conn, status, "private-title-and-token") end

      assert {:error, ^reason} =
               TmdbMovieProvider.search("Film", nil, token: "secret", plug: plug)
    end
  end

  test "rejects oversized or malformed responses without returning raw data" do
    oversized = fn conn -> Plug.Conn.resp(conn, 200, String.duplicate("x", 1_048_577)) end
    malformed = fn conn -> Plug.Conn.resp(conn, 200, "private-broken-json") end

    assert {:error, :invalid_response} =
             TmdbMovieProvider.search("Film", nil, token: "secret", plug: oversized)

    assert {:error, :invalid_response} =
             TmdbMovieProvider.search("Film", nil, token: "secret", plug: malformed)
  end
end
