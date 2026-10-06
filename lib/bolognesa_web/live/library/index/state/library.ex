defmodule BolognesaWeb.Library.Index.State.Library do
  @moduledoc false
  alias Bolognesa.Libraries.Domain.{Library, Scan, ScanStatus}

  defstruct [
    :id,
    :name,
    :path,
    :state,
    :state_label,
    :error,
    :last_completed_at,
    :inspection_summary,
    :inspection_counts,
    :inspection_failure_reasons,
    files_discovered: 0,
    attempt: 0,
    active?: false,
    inspection_active?: false,
    button_label: "Escanear"
  ]

  @type t :: %__MODULE__{
          id: Library.id(),
          name: String.t(),
          path: String.t(),
          state: atom(),
          state_label: String.t(),
          error: String.t() | nil,
          last_completed_at: String.t() | nil,
          inspection_summary: String.t(),
          inspection_counts: map(),
          inspection_failure_reasons: list(map()),
          files_discovered: non_neg_integer(),
          attempt: non_neg_integer(),
          active?: boolean(),
          inspection_active?: boolean(),
          button_label: String.t()
        }

  @empty_counts %{
    uninspected: 0,
    pending: 0,
    running: 0,
    succeeded: 0,
    failed: 0,
    failure_reasons: %{}
  }

  @spec from_domain(Library.t(), ScanStatus.t(), map()) :: t()
  def from_domain(library, status, counts \\ @empty_counts) do
    scan = status.latest_scan

    %__MODULE__{
      id: library.id,
      name: library.name,
      path: library.path,
      state: state(scan),
      state_label: label(state(scan)),
      active?: scan != nil and Scan.active?(scan),
      files_discovered: if(scan, do: scan.files_discovered, else: 0),
      attempt: if(scan, do: scan.attempt, else: 0),
      error: failure(scan),
      last_completed_at: format_date(status.last_completed_at),
      inspection_counts: counts,
      inspection_summary: summary(counts),
      inspection_failure_reasons: failure_reasons(counts),
      inspection_active?: counts.pending + counts.running > 0,
      button_label: if(state(scan) == :failed, do: "Reintentar", else: "Escanear")
    }
  end

  defp summary(counts) do
    "Análisis: #{counts.pending} pendientes, #{counts.running} en curso, " <>
      "#{counts.succeeded} correctos, #{counts.failed} análisis técnicos con error" <>
      if(counts.uninspected > 0, do: ", #{counts.uninspected} sin analizar", else: "")
  end

  defp failure_reasons(counts) do
    counts
    |> Map.get(:failure_reasons, %{})
    |> Enum.sort_by(fn {reason, _count} -> to_string(reason) end)
    |> Enum.map(fn {reason, count} ->
      %{reason: reason, count: count, label: inspection_message(reason)}
    end)
  end

  defp inspection_message(:source_changed), do: "El archivo cambió desde el escaneo"
  defp inspection_message(:source_inaccessible), do: "No se puede acceder al archivo"
  defp inspection_message(:unsafe_entry), do: "La entrada no se puede analizar de forma segura"
  defp inspection_message(:unreadable), do: "No se pudo leer el archivo"
  defp inspection_message(:unsupported), do: "Formato no admitido"
  defp inspection_message(:timeout), do: "Se agotó el tiempo de análisis"
  defp inspection_message(:tool_unavailable), do: "Herramienta de análisis no disponible"
  defp inspection_message(:invalid_output), do: "No se pudieron interpretar los datos técnicos"
  defp inspection_message(:storage_unavailable), do: "Almacenamiento no disponible"
  defp inspection_message(:attempts_exhausted), do: "Se agotaron los reintentos"
  defp inspection_message(:unexpected_failure), do: "Error inesperado durante el análisis"
  defp inspection_message(_), do: "No se pudo completar el análisis"

  defp state(nil), do: :not_scanned
  defp state(scan), do: scan.state
  defp label(:not_scanned), do: "Pendiente de escaneo"
  defp label(:queued), do: "En cola"
  defp label(:running), do: "Escaneando"
  defp label(:retrying), do: "Esperando reintento"
  defp label(:completed), do: "Escaneo completado"
  defp label(:failed), do: "Escaneo interrumpido"
  defp format_date(nil), do: nil
  defp format_date(date), do: Calendar.strftime(date, "%d/%m/%Y %H:%M UTC")
  defp failure(%Scan{failure_reason: reason}) when reason != nil, do: message(reason)
  defp failure(_), do: nil
  defp message(:source_inaccessible), do: "No se puede leer la carpeta de origen."
  defp message(:source_outside_roots), do: "La carpeta está fuera de las ubicaciones permitidas."
  defp message(:source_changed), do: "La carpeta cambió durante el escaneo. Vuelve a intentarlo."
  defp message(:entry_unreadable), do: "No se pudo leer todo el contenido de la carpeta."

  defp message(:unsafe_entry),
    do: "La carpeta contiene un enlace o una entrada que no se puede escanear."

  defp message(:storage_unavailable), do: "El almacenamiento está temporalmente indisponible."
  defp message(:timeout), do: "El escaneo superó el tiempo disponible."

  defp message(:attempts_exhausted),
    do: "Se agotaron los intentos automáticos. Puedes reintentar."

  defp message(_), do: "No se pudo completar el escaneo. Puedes reintentar."
end
