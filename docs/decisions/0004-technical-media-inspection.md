# 0004. Inspección técnica por revisión con trabajos duraderos

Estado: aceptada por el propietario al aprobar la especificación H2c el 2026-10-05; implementación pendiente.

## Contexto

H2b inventaría archivos sin abrirlos. H2c debe extraer duración, contenedor y pistas sin modificar originales, recuperar trabajos interrumpidos y evitar que un resultado antiguo sobrescriba el vigente. El inventario identifica revisiones por tamaño y modificación con precisión de segundos: ciertos cambios de contenido pueden conservar ambos valores.

## Decisión

Solicitar inspección para archivos nuevos, aún sin análisis, modificados o restaurados. Un escaneo normal de archivos sin cambios reutiliza los datos técnicos; una opción explícita «Reanalizar» fuerza nuevas solicitudes durante el recorrido. Se acepta que una sustitución con igual tamaño y fecha puede pasar inadvertida; el análisis no acredita identidad criptográfica del contenido.

Confirmar cada lote del inventario, el estado de inspección y un evento de outbox en una misma transacción. Un despachador recuperable crea trabajos Oban desde eventos confirmados. Cada solicitud tiene un token nuevo; los resultados solo se guardan si token, revisión y disponibilidad siguen vigentes. Limitar la cola de inspección inicialmente a un trabajo simultáneo por instancia y medir antes de aumentarla.

El adaptador de `ffprobe` revalida la ruta física, lee únicamente metadatos técnicos permitidos y no persiste su salida completa ni datos privados. Se ejecuta fuera de transacciones con límites de tiempo y salida. Los fallos de un archivo no detienen los demás.

## Consecuencias y alternativas

El outbox añade tabla y despachador, pero conserva la atomicidad acordada para consecuencias duraderas y permite recuperarlas tras reinicios. Insertar trabajos directamente en la transacción sería más corto, aunque haría del motor de trabajos el único registro del evento de descubrimiento. Inspeccionar todos los archivos en cada escaneo evitaría reutilizar datos ante cambios invisibles para H2b, a costa de leer repetidamente toda la biblioteca en el QNAP. Calcular huellas completas aumentaría lecturas y complejidad; se revisará si aparece una necesidad real.

La decisión no valida recuperación en el QNAP ni compatibilidad de reproducción. Las garantías de carreras del sistema de archivos siguen limitadas por la falta de una instantánea atómica.

## Referencias

- [Especificación H2c](../plans/h2-media-inspection-design.md).
- [Decisión 0003](0003-recoverable-library-scans.md) y [convención de backend](../conventions/backend.md).
