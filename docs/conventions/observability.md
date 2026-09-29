# Observabilidad

Por ahora la observabilidad propia de Bolognesa se basa en logs parametrizados con `Logger`: mensajes estables y campos de contexto como metadata. No se añaden plataformas de métricas ni trazas en esta fase. La instrumentación incluida en la base Phoenix puede permanecer.

```elixir
Logger.info("Library scan completed",
  library_id: library_id,
  scan_id: scan_id,
  files_discovered: count,
  duration_ms: duration_ms
)
```

## Convenciones

- Mantener mensajes estables; colocar identificadores, contadores, duraciones y motivos en metadata en lugar de interpolarlos en el texto.
- Configurar el formatter para mostrar explícitamente los campos aprobados. Añadir metadata a una llamada no garantiza por sí solo que aparezca en la salida.
- Registrar inicio y resultado de trabajos relevantes, reintentos y fallos que requieran diagnóstico. Evitar un mensaje por cada operación trivial o actualización de reproducción.
- Usar `debug` para detalle de diagnóstico, `info` para hitos operativos normales, `warning` para degradaciones o reintentos y `error` para fallos definitivos o inesperados.
- Relacionar mensajes mediante los identificadores disponibles: petición, trabajo, evento, escaneo o archivo. Pasar el contexto necesario explícitamente al iniciar trabajo asíncrono; no asumir que la metadata del proceso padre se hereda.
- Registrar cada fallo en la capa que conoce su resultado operativo. Evitar que todas las capas registren el mismo error al propagarlo.
- Usar motivos acotados y seguros. No volcar indiscriminadamente structs, respuestas externas, parámetros o excepciones con datos sensibles.
- Excluir contraseñas, tokens, cookies, credenciales, rutas completas innecesarias y listados privados de contenido. Preferir identificadores internos.
- El dominio no depende de `Logger`; la aplicación y los adaptadores registran los resultados en sus límites.

Los logs no sustituyen los estados persistidos de trabajos, el outbox ni el feedback de la interfaz. Tampoco se convierten en requisitos de prueba para cada operación: comprobar su contenido solo cuando exista un contrato operativo o de confidencialidad relevante.

Esta es una convención para la futura implementación. La configuración de logging generada por Phoenix no ha sido adaptada todavía a todos estos campos.
