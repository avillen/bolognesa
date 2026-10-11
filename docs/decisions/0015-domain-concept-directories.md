# 0015. Directorios de conceptos del dominio

Estado: aceptada e implementada localmente el 2026-10-11 en los contextos con dominio; sin publicación ni despliegue.

## Contexto

Los contextos ya separan dominio, aplicación e infraestructura, pero sus módulos de dominio conviven en un único directorio. Identificación ha acumulado entidades, candidatos, selecciones y reglas de decisión. Se busca que DDD y la arquitectura hexagonal sean visibles en la navegación del código sin crear categorías artificiales.

## Decisión

- Dentro de `domain/`, organizar módulos por tipo de concepto: `entities/`, `value_objects/`, `policies/` y `services/`.
- Crear solo las categorías necesarias. Dentro de ellas, permitir subdirectorios por subdominio cuando exista un grupo cohesionado; evitar carpetas por módulo y categorías vacías.
- Usar namespaces que reflejen las rutas, por ejemplo `Context.Domain.Entities.Nombre`.
- No crear `aggregates/` como categoría paralela: la raíz de agregado suele ser una entidad y se reconoce por las reglas y límites de consistencia que controla.
- Clasificar proyecciones y modelos auxiliares por su semántica, identidad y ciclo de vida, no de forma automática por el nombre de archivo.
- Reservar `services/` para reglas de dominio que no pertenezcan naturalmente a una entidad, objeto de valor o política.
- Aplicar primero el criterio a Identificación: `Identification` es entidad; candidatos, detalles, hints y selecciones son objetos de valor agrupados bajo `movies/` y `series/`; `SeriesMatch` es política; `FileToIdentify` y los modelos de revisión son proyecciones bajo `read_models/`. `NewMovie` es un objeto de valor de entrada previa a persistencia, ubicado junto a los conceptos de película.
- Mantener los límites del contexto, las fachadas, contratos de puertos, persistencia y comportamiento. Las reglas distintas de películas y series no se unifican por compartir una ubicación.

## Consecuencias

Los módulos ganaron segmentos de namespace y sus consumidores, aliases y pruebas se actualizaron. Catálogo usa `read_models/movies/`, `read_models/series/` y `read_models/catalog_entry.ex` para la proyección de identidad común; los ports y adaptadores lectores de películas se llaman `MoviesReader` y `EctoMoviesReader`. Identidad usa `entities/`, `value_objects/sessions/` y `read_models/`; Bibliotecas usa `entities/`, `value_objects/files/`, `value_objects/inspection/` y `read_models/scans/`; Reproducción usa `value_objects/`, `policies/` y `read_models/`. La organización hace visibles los conceptos DDD, pero requiere criterio para no sobredimensionar carpetas ni convertir la clasificación en taxonomía rígida. No cambian fachadas, puertos, persistencia ni comportamiento observable.

## Referencias

- [Convenciones de backend](../conventions/backend.md)
- [Diseño de responsabilidades de Identificación](../designs/2026-10-11-identification-responsibilities.md)
