# 0008. Schemas Ecto en un namespace de persistencia global

Estado: aceptada e implementada localmente el 2026-10-10; ubicación revisada el 2026-10-11, sin nuevo despliegue.

## Contexto

Los schemas Ecto estaban anidados en los módulos de repositorio de cada contexto. Los adaptadores de lectura de Catálogo, Identificación y Reproducción importan varios de esos schemas para consultas entre tablas. El namespace anterior hacía parecer que el schema pertenecía a un repositorio concreto, aunque representa una tabla compartida por la aplicación.

## Decisión

- Situar los schemas Ecto en `lib/bolognesa/infrastructure/persistence/`, bajo `Bolognesa.Infrastructure.Persistence`, con un módulo por tabla y sin subcarpetas por contexto.
- Usar nombres únicos en el namespace global. Las tablas de eventos se representan con `IdentificationEventSchema` e `InspectionEventSchema`.
- Cada adaptador Ecto importa los schemas necesarios para sus consultas. Los mappers permanecen junto a los repositorios que los usan.
- Mantener los puertos, fachadas y reglas de escritura de los contextos. Compartir un schema no autoriza a otro contexto a escribir sus datos.

## Consecuencias

Las consultas de infraestructura ya no dependen del namespace de un repositorio ajeno. El namespace global facilita joins y exige elegir nombres de schema únicos. El traslado cambia nombres de módulos y referencias en código y pruebas; no cambia tablas, campos, migraciones ni datos persistidos. Las proyecciones que cruzan contextos siguen encapsuladas en adaptadores de lectura.

## Revisión de ubicación — 2026-10-11

Por indicación del propietario, los schemas globales pasan de `lib/bolognesa/persistence/` y `Bolognesa.Persistence` a `lib/bolognesa/infrastructure/persistence/` y `Bolognesa.Infrastructure.Persistence`. La ubicación hace explícita su pertenencia a infraestructura; se conservan schemas compartidos, propietarios de escritura y mappers locales a cada adaptador. El cambio actualiza referencias de código y pruebas, sin migraciones de base de datos.
