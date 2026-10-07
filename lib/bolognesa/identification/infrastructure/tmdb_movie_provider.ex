defmodule Bolognesa.Identification.Infrastructure.TmdbMovieProvider do
  @moduledoc "TMDb v3 adapter using bounded Req requests."
  @behaviour Bolognesa.Identification.Application.Ports.MovieProvider

  alias Bolognesa.Identification.Infrastructure.TmdbResponse

  @base_url "https://api.themoviedb.org/3"
  @max_bytes 1_048_576

  @impl true
  def search(query, year), do: search(query, year, [])

  @spec search(binary(), integer() | nil, keyword()) ::
          {:ok, [Bolognesa.Identification.Domain.MovieCandidate.t()]}
          | {:error, Bolognesa.Identification.Application.Ports.MovieProvider.reason()}
  def search(query, year, opts) when is_binary(query) do
    params = [query: query, language: "es-ES", include_adult: false, page: 1]
    params = if is_integer(year), do: Keyword.put(params, :year, year), else: params

    with {:ok, body} <- get("/search/movie", params, opts) do
      TmdbResponse.search(body)
    end
  end

  @impl true
  def details(id), do: details(id, [])

  @spec details(pos_integer(), keyword()) ::
          {:ok, Bolognesa.Identification.Domain.MovieDetails.t()}
          | {:error, Bolognesa.Identification.Application.Ports.MovieProvider.reason()}
  def details(id, opts) when is_integer(id) and id > 0 do
    with {:ok, body} <- get("/movie/#{id}", [language: "es-ES"], opts),
         {:ok, details} <- TmdbResponse.details(body) do
      if details.provider_id == id, do: {:ok, details}, else: {:error, :invalid_response}
    end
  end

  defp get(path, params, opts) do
    token = Keyword.get(opts, :token, Application.get_env(:bolognesa, :tmdb_read_token))

    if is_binary(token) and token != "" do
      request(path, params, token, opts)
    else
      {:error, :not_configured}
    end
  end

  defp request(path, params, token, opts) do
    request_opts = [
      url: @base_url <> path,
      headers: [{"authorization", "Bearer " <> token}, {"accept", "application/json"}],
      params: params,
      receive_timeout: 5_000,
      retry: false,
      decode_body: false,
      into: &collect_bounded/2
    ]

    request_opts =
      case Keyword.fetch(opts, :plug) do
        {:ok, plug} -> Keyword.put(request_opts, :plug, plug)
        :error -> request_opts
      end

    case Req.get(request_opts) do
      {:ok, response} -> normalize_response(response)
      {:error, _error} -> {:error, :provider_unavailable}
    end
  rescue
    _exception -> {:error, :provider_unavailable}
  end

  defp collect_bounded({:data, chunk}, {request, response}) do
    body = response.body

    if is_binary(body) and byte_size(body) + byte_size(chunk) <= @max_bytes do
      {:cont, {request, %{response | body: body <> chunk}}}
    else
      {:halt, {request, %{response | body: :too_large}}}
    end
  end

  defp normalize_response(%Req.Response{status: 200, body: body})
       when is_binary(body) and byte_size(body) <= @max_bytes,
       do: {:ok, body}

  defp normalize_response(%Req.Response{status: status}) when status in [401, 403],
    do: {:error, :unauthorized}

  defp normalize_response(%Req.Response{status: 404}), do: {:error, :not_found}
  defp normalize_response(%Req.Response{status: 429}), do: {:error, :rate_limited}

  defp normalize_response(%Req.Response{status: status}) when status >= 500,
    do: {:error, :provider_unavailable}

  defp normalize_response(_response), do: {:error, :invalid_response}
end
