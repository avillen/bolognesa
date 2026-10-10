# 0009. Resultados de dominio en los repositorios

Estado: aceptada el 2026-10-10; contratos identificados adaptados localmente.

## Contexto

Los lectores de Catálogo e Identificación ya convierten schemas Ecto en modelos de dominio y dejan a los casos de uso la construcción de DTOs. Otros puertos aún devuelven mapas o schemas, lo que permite que detalles de persistencia o estructuras sin nombre lleguen a la aplicación.

## Decisión

- Los resultados de repositorio que contienen datos de negocio utilizan modelos de dominio. No exponen schemas Ecto, DTOs de aplicación ni mapas libres.
- Las lecturas compuestas pueden devolver colecciones o tuplas tipadas de modelos de dominio junto con metadatos escalares explícitos. El caso de uso construye el DTO público cuando lo necesita.
- Las operaciones sin entidad pueden devolver confirmaciones, booleanos, identificadores, contadores o estados definidos en su puerto. Los mapas de atributos de entrada no quedan prohibidos por esta regla.

## Consecuencias

Los límites de persistencia expresan mejor qué datos entregan y evitan que los consumidores dependan de Ecto o de claves de mapas implícitas. Algunas lecturas pueden cargar más campos para reconstruir entidades completas; se evaluará ese coste en cada consulta.

Los contratos que motivaron esta decisión se adaptaron: `InspectionRepository.get/1` y `EctoIdentificationRepository.get/1` devuelven entidades de dominio; `InspectionRepository.counts/1` devuelve `InspectionCounts`; `IdentificationRepository.begin_identification/3` devuelve `FileToIdentify` del propio contexto de Identificación; y `PlaybackRepository.find_source/2` devuelve `Source`. No se modificaron tablas ni migraciones. La proyección local de Identificación se concretó en la [decisión 0010](0010-context-owned-models.md).
