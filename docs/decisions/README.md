# Decisiones de arquitectura

Las [convenciones](../conventions/backend.md) contienen las reglas vigentes. Los registros de esta carpeta explican por qué se tomaron decisiones significativas y qué costes se aceptaron.

Crear un registro cuando se elija o cambie un límite arquitectónico, contrato o dependencia relevante. No se necesita uno por cada detalle de implementación. Usar nombres `NNNN-tema.md` y documentar contexto, decisión, consecuencias y estado. Si una decisión cambia, marcarla como sustituida y enlazar la nueva; actualizar también la convención vigente.

| Registro | Estado | Decisión |
| --- | --- | --- |
| [0001](0001-architecture-foundation.md) | Aceptada | Aplicación única con DDD independiente de Ecto y frontend LiveView por pantalla |
| [0002](0002-initial-access.md) | Aceptada | Alta inicial única y sesiones revocables limitadas a la LAN HTTP |
| [0003](0003-recoverable-library-scans.md) | Aceptada; implementada, recuperación QNAP no validada | Escaneos Oban/PostgreSQL, identidad por ruta relativa y generaciones por invocación |
| [0004](0004-technical-media-inspection.md) | Aceptada; implementación pendiente | Inspección por revisión, outbox y token para descartar resultados antiguos |
| [0005](0005-catalog-identification.md) | Aceptada; implementación local, integración real pendiente | Películas TMDb, solicitudes con inventario y corrección manual protegida |
