# 0012. Identidad común del catálogo y escritura desde Identificación

Estado: implementada localmente el 2026-10-11; sin despliegue.

## Contexto

Las asociaciones y la autorización de reproducción dependían de `movies`. Preparar series requiere una referencia única con integridad referencial y detalles propios de cada clase. La entrega mantiene únicamente películas.

## Decisión

- `catalog_entries` guarda ID, clase y referencia externa única `(provider, resource_type, provider_id)`. Los valores admitidos son `movie`, `tmdb`, `movie` y un entero positivo. Incorporar otra clase requiere una migración y contratos reales.
- `movies.id` es PK y FK restrictiva de la identidad común, sin generación independiente. Sus columnas contienen únicamente metadatos específicos. Se preservan los IDs existentes y las URLs.
- Identificación crea o reutiliza identidad y detalles mediante un colaborador privado de su repositorio, con entrada validada propia. La asociación `catalog_entry_id`, los detalles y la identidad se confirman en una única transacción. Los reintentos conservan los metadatos existentes; la unicidad resuelve versiones concurrentes.
- Catálogo consulta las obras y reconstruye sus modelos y DTOs propios desde joins de schemas globales. No importa modelos ni mappers de Identificación. Se retiran el puerto/escritor de Catálogo y `Catalog.upsert_in_transaction!/2`.
- Reproducción valida el par elemento–archivo contra identidad e identificación confirmada, sin depender de `MovieSchema`. HLS conserva actor, elemento, archivo y revisión en cada petición. Las rutas de película traducen `movie_id` en la frontera.
- Tokens, estados, revisiones, correcciones, eventos y argumentos de Oban se preservan. Consultas externas quedan fuera de transacciones.

Esta decisión sustituye parcialmente la [0005](0005-catalog-identification.md) en identidad, referencia y propietario de escritura, incluida su excepción de transacción entre contextos. Permanecen sus reglas de proveedor, atomicidad, protección manual y recuperación.

## Consecuencias y operación

Las lecturas de película añaden un join y cada contexto mantiene representaciones locales. Si aparece un alta de obras independiente de identificar archivos, se revisará su propietario con ese caso concreto.

Las tres migraciones y el código requieren una actualización coordinada: detener la aplicación antigua, migrar y reiniciar con la versión nueva. Los estados intermedios no son publicables. El rollback reconstruye referencias externas y asociaciones y ajusta la secuencia de películas, incluyendo altas posteriores a la migración.

La comprobación usa exclusivamente `bolognesa_catalog_migration_check`, con datos sintéticos y Repo dedicado; no se ejecuta en QNAP. No se introducen series, progreso ni protocols. Un protocol requiere dos structs reales, operación común con la misma semántica y un consumidor que se simplifique.

## Referencias

- [Diseño](../designs/2026-10-11-catalog-expansion-design.md)
- [Plan y verificaciones](../plans/2026-10-11-catalog-expansion.md)
- [Modelos propios por contexto](0010-context-owned-models.md)
