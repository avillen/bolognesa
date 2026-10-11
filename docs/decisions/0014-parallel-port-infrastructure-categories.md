# 0014. Categorías paralelas para ports e infraestructura

Estado: aceptada e implementada localmente sobre `main` el 2026-10-11. Sin publicación ni despliegue.

## Contexto

Los ports de los contextos convivían en un único directorio aunque representaban repositorios, readers, proveedores externos y servicios técnicos. En infraestructura, los adaptadores se agrupaban por carpetas como `persistence` y por archivos sueltos, así que no se veía de inmediato qué contrato implementaba cada módulo.

## Decisión

Cada contexto organiza `Application.Ports` e `Infrastructure` en categorías paralelas: `Repositories`, `Readers`, `Providers` y `Services`. Cada behaviour y adaptador conserva su nombre descriptivo y callbacks. La categoría refleja la responsabilidad del contrato; por eso un adaptador Ecto puede estar en `Infrastructure.Readers` o `Infrastructure.Repositories`.

`Services` agrupa puertos técnicos como hashing, descubrimiento/lectura local de archivos y análisis multimedia. Los mappers y colaboradores internos permanecen junto a la categoría responsable. Los schemas globales permanecen en `Bolognesa.Infrastructure.Persistence`; workers y políticas siguen en `Infrastructure.Jobs`; módulos de infraestructura sin port directo no se trasladan por simetría.

## Consecuencias

Los namespaces y rutas hacen visibles las familias de contratos y facilitan ubicar sus adaptadores y referencias. El movimiento requiere actualizar aliases en casos de uso, fachadas, pruebas y configuración. No cambia ningún callback, fachada pública, almacenamiento, migración ni comportamiento. La correspondencia refleja el tipo del contrato y no oculta que varias categorías usan Ecto.

## Referencias

- [Diseño](../designs/2026-10-11-port-infrastructure-categories.md)
- [Plan](../plans/2026-10-11-port-infrastructure-categories.md)
- [Convención de backend](../conventions/backend.md)
