# Decisiones de arquitectura

Las [convenciones](../conventions/backend.md) contienen las reglas vigentes. Los registros de esta carpeta explican por qué se tomaron decisiones significativas y qué costes se aceptaron.

Crear un registro cuando se elija o cambie un límite arquitectónico, contrato o dependencia relevante. No se necesita uno por cada detalle de implementación. Usar nombres `NNNN-tema.md` y documentar contexto, decisión, consecuencias y estado. Si una decisión cambia, marcarla como sustituida y enlazar la nueva; actualizar también la convención vigente.

| Registro | Estado | Decisión |
| --- | --- | --- |
| [0001](0001-architecture-foundation.md) | Aceptada | Aplicación única con DDD independiente de Ecto y frontend LiveView por pantalla |
