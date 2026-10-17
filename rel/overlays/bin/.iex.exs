admin =
  case Bolognesa.Release.fetch_authenticated_admin() do
    {:ok, actor} -> actor
    :not_found -> nil
    {:error, reason} -> raise "Cannot resolve administrator: #{inspect(reason)}"
  end
