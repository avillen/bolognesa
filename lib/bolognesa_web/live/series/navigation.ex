defmodule BolognesaWeb.Series.Navigation do
  @moduledoc "Validated return context for the series browsing hierarchy."
  import Phoenix.Component, only: [assign: 2]

  @spec assign_context(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def assign_context(socket, params) do
    series_params =
      socket.assigns.library_params
      |> put_query(params["catalog_query"])
      |> put_page(:catalog_page, params["catalog_page"])

    catalog_params =
      socket.assigns.library_params
      |> copy_param(:query, series_params[:catalog_query])
      |> copy_param(:page, series_params[:catalog_page])

    season_params = put_page(series_params, :page, params["season_page"])

    assign(socket,
      series_params: series_params,
      catalog_params: catalog_params,
      season_params: season_params
    )
  end

  @spec episode_params(map(), pos_integer()) :: map()
  def episode_params(series_params, page), do: put_page(series_params, :season_page, page)

  @spec episode_target_params(map(), pos_integer(), map()) :: map()
  def episode_target_params(series_params, page, target) do
    params = episode_params(series_params, page)

    case Map.get(target, :part_number) do
      nil -> params
      part -> Map.put(params, :part, part)
    end
  end

  defp put_query(params, query) when is_binary(query) and query != "",
    do: Map.put(params, :catalog_query, query)

  defp put_query(params, _), do: params

  defp put_page(params, key, page) when is_integer(page) and page > 1 and page <= 100_000,
    do: Map.put(params, key, page)

  defp put_page(params, key, text) when is_binary(text) do
    case Integer.parse(text) do
      {page, ""} -> put_page(params, key, page)
      _ -> params
    end
  end

  defp put_page(params, _key, _page), do: params
  defp copy_param(params, _key, nil), do: params
  defp copy_param(params, key, value), do: Map.put(params, key, value)
end
