# 0010. Modelos propios por contexto

Estado: aceptada e implementada localmente el 2026-10-10; sin nuevo despliegue.

## Contexto

Los lectores de Catálogo e Identificación componían respuestas con `MediaFile`, `Identification` o `Movie` de otros contextos y reutilizaban sus mappers. El repositorio de Identificación también devolvía `Libraries.MediaFile` para inferir un título. Esos contratos dependían de campos y módulos ajenos que podían cambiar por motivos propios del contexto propietario.

## Decisión

- Cada contexto representa sus lecturas y operaciones con modelos propios que contienen únicamente los datos necesarios. Repetir unos campos entre contextos es preferible a compartir una entidad por conveniencia.
- Los módulos internos de un contexto no se llaman desde otro. Las operaciones entre contextos pasan por fachadas públicas y prefieren identificadores cuando son suficientes. La escritura de solicitudes de Identificación dentro de la transacción del inventario conserva su atomicidad mediante una operación de fachada.
- Los schemas Ecto continúan en `Bolognesa.Infrastructure.Persistence` para consultas entre tablas. La validación física de rutas, que comparten Bibliotecas y Reproducción, se ubica en `Bolognesa.Infrastructure` como utilidad técnica neutral.
- `Identity.Domain.Actor` continúa como contrato explícito de identidad autenticada para operaciones protegidas; no se usa para modelar datos de negocio de los otros contextos.

## Consecuencias

Catálogo usa su propia versión de película; Identificación usa proyecciones locales para el archivo que identifica y las filas de revisión. Los lectores dejan de depender de mappers ajenos. Se duplican unos pocos campos y conversiones, pero los cambios de un modelo ya no obligan a modificar contratos de otros contextos. No cambian tablas, migraciones ni reglas de autorización.

## Referencias

- [Plan de adaptación](../plans/context-owned-models.md)
