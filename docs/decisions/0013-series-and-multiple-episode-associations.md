# 0013: series y asociaciones múltiples por archivo

Estado: aceptada e implementada localmente sobre `main`. Sin publicación ni despliegue de series. Fecha: 2026-10-11.

## Contexto

El propietario mantiene películas y series en carpetas separadas y solicita especiales y archivos con varios episodios. La referencia singular introducida en [0012](0012-catalog-entry-identity.md) conserva identidad de películas, pero no representa un archivo que contiene varios episodios sin confundir obra y soporte físico.

## Decisión

Cada biblioteca declara un tipo inmutable `movie` o `series`; las bibliotecas previas migran a películas. El inventario y la inspección técnica siguen usando archivo, token y revisión. Los argumentos encolados de Oban conservan archivo y token; el trabajador consulta el tipo vigente.

`catalog_entries` admite `movie`, `series`, `season` y `episode`. Su referencia externa es única por proveedor y clase de recurso. Los detalles mantienen PK/FK de identidad propia. Cada temporada pertenece a una serie y cada episodio a una temporada; temporada cero representa especiales, con episodios positivos. No se crea la jerarquía completa de TMDb por adelantado.

Una decisión por archivo conserva estado, revisión, token y protección manual. `identification_entries` almacena sus elementos confirmados con posiciones positivas y únicas, sin duplicar un elemento dentro de la decisión. Una película tiene una asociación; una selección de serie contiene entre uno y cien episodios únicos de una sola temporada, ordenados por número. Los estados sin confirmación no exponen asociaciones vigentes.

Identificación valida el conjunto completo y escribe identidad, detalles, decisión y relaciones en una transacción. La información HTTP se consulta fuera de la transacción; al guardar se comprueban token, revisión, disponibilidad y protección manual bajo bloqueo. Una respuesta incompleta no confirma un subconjunto. Los conflictos de jerarquía provocan rollback, conservando la decisión anterior. Catálogo y Reproducción leen modelos propios mediante sus adaptadores y fachadas.

La coincidencia automática exige título normalizado y año explícito coincidentes, sin varios resultados equivalentes. Los nombres ambiguos, episodios ausentes o numeraciones no interpretables requieren revisión. La corrección manual sustituye el conjunto íntegro; también puede retirar toda identificación. La ficha de episodio permite corregir su archivo aunque ya no figure en la cola.

La entrega acepta películas y episodios confirmados. Las rutas de serie y temporada no conceden reproducción. Un archivo múltiple se reproduce completo desde su principio, con aviso visible; no se inventan cortes ni progreso por episodio. Directo y HLS comparten controles de actor, asociación, archivo, disponibilidad y revisión. Una sesión HLS de un episodio no se reutiliza para otro, aunque compartan archivo.

## Migración y reversión

Las relaciones confirmadas previas se conservan en posición uno. Referencias residuales de decisiones `pending` o `failed` no se convierten en asociaciones vigentes: el lector antiguo ya las rechazaba para reproducción. Se conservan IDs de películas, metadatos, decisiones, tokens, eventos y argumentos de trabajos.

El rollback rechaza bibliotecas de series, incluso sin identificar; también identidades de series o decisiones con más de una asociación. Cada guardia se ejecuta antes de retirar tablas o columnas. No se colapsan asociaciones ni se cambia silenciosamente una fuente de series a películas. Para volver al código anterior con esos datos es necesaria una restauración coherente de backup.

Las migraciones y el código deben activarse de forma coordinada, con la aplicación antigua detenida. El verificador usa exclusivamente `bolognesa_series_migration_check`, un Repo dedicado y datos sintéticos; verifica ida/vuelta, reaplicación, secuencias y rechazo sin pérdida. El verificador previo de 0012 queda acotado a sus tres migraciones, en su propia base desechable. Ambos se ejecutan con `MIX_ENV=test mix run --no-start`, rechazan un supervisor o Repo normal ya arrancado e inician únicamente dependencias de Ecto/PostgreSQL después de sus guardas. Ninguno arranca la aplicación ni migra su Repo.

## Costes y límites

La asociación múltiple añade joins y exige sustituir relaciones de forma atómica. Las consultas paginadas evitan cargar una serie completa, aunque las fichas conservan versiones ausentes para explicar su disponibilidad. La inspección técnica se muestra solo si corresponde a la revisión vigente. TMDb sigue siendo una dependencia externa, con transporte y selección acotados.

No se implementan reproducción automática del siguiente episodio, cortes del archivo múltiple, numeración absoluta ni identificación por fecha. La verificación automatizada local no acredita dispositivos, rendimiento del NAS ni despliegue. [Diseño](../designs/2026-10-11-series-design.md), [plan](../plans/2026-10-11-series.md) y [registro de ejecución](../history/2026-10-11-series-execution.md).
