# 0003. Escaneo persistido con generaciones por intento

Estado: aceptada por el propietario al aprobar la especificación H2b el 2026-10-03. Implementación pendiente.

## Contexto

H2a registra fuentes pero no inventario. El siguiente recorrido necesita persistencia, ejecución fuera de la petición web, recuperación tras interrupción y protección frente a resultados antiguos. El despliegue tiene una aplicación y PostgreSQL en QNAP; no hay evidencia para elevar la concurrencia.

## Decisión

Usar Oban gratuito con PostgreSQL como adaptador de ejecución duradera, inicialmente en la rama `~> 2.19.4`. El dominio no depende del motor. Encolar el trabajo en la misma transacción que la solicitud. La base impone un escaneo activo por biblioteca; una cola con concurrencia 1 limita la ejecución en la única instancia prevista.

Cada invocación adquiere una generación nueva. El guardado de lotes, la finalización y el registro de fallos comprueban esa generación en la misma transacción que sus efectos. Un reintento repite el recorrido desde el principio y conserva los lotes confirmados; solo su recorrido completo permite marcar ausencias.

Identidad de archivo por biblioteca y ruta relativa, preservando los bytes originales. Tamaño y modificación determinan su revisión; no se reconoce un renombrado como el mismo archivo ni se deduplica por contenido. Un recorrido parcial conserva disponibilidad previa de entradas no encontradas.

La recuperación del motor se complementa con reconciliación del resultado persistido de dominio. La interfaz consulta estado durable; H2b no tiene consecuencias independientes que justifiquen un outbox. H2c deberá introducir atomicidad para trabajos de inspección cuando se implemente, conforme a las convenciones existentes.

## Alternativas y costes

- Una cola propia con PostgreSQL permitiría control total, pero añade implementación y mantenimiento de coordinación y recuperación.
- Tareas OTP sin persistencia no cubren por sí mismas la recuperación solicitada.
- Seguir desde un cursor de disco exigiría mantener un snapshot fiable del árbol; repetir desde el principio reduce complejidad a costa de volver a visitar entradas.

Oban añade tablas y una dependencia. Lifeline rescata por tiempo y puede provocar duplicados; las generaciones son una garantía de aplicación, no una promesa de ejecución exactamente una vez. El límite de cola no es global si se añaden instancias. Los presupuestos y la capacidad deberán medirse en QNAP; no se declara validación real por aprobar el diseño.

## Referencias

- [Especificación](../plans/h2-library-scan-design.md) y [plan](../plans/h2-library-scan.md).
- [Oban 2.19.4](https://oban.hexdocs.pm/2.19.4/Oban.html) y [Lifeline](https://oban.hexdocs.pm/2.19.4/Oban.Plugins.Lifeline.html).
