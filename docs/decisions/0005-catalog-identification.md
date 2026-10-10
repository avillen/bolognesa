# 0005. Catálogo de películas e identificación por TMDb

Estado: aceptada para la implementación local de H3 el 2026-10-07; desplegada en QNAP; revisión manual pendiente.

## Contexto

El inventario H2 guarda archivos y revisiones, pero no conoce obras. H3 necesita reconocer películas, agrupar varios archivos de una obra y permitir correcciones que sobrevivan a escaneos y trabajos antiguos. El propietario aprobó TMDb, el envío de títulos inferidos del nombre de archivo y la selección automática del primer resultado válido, con revisión manual posterior.

## Decisión

- `Movie` tiene identidad interna y referencia única `(provider, provider_id)`. La asociación archivo–obra vive en Identificación, con estado, procedencia, revisión observada y token de solicitud.
- Bibliotecas solicita a la fachada de Identificación que escriba la solicitud y el evento outbox en la misma transacción que el lote de inventario. La fachada delega en `EctoRequestWriter`; el despachador entrega el evento a Oban tras el commit.
- El proveedor recibe solo el título extraído del nombre base y el año inferido; no recibe rutas, biblioteca ni contenido. La consulta con Req se hace fuera de la transacción y usa `TMDB_READ_TOKEN` como token de lectura en runtime. Sin token, el trabajo termina con estado visible `not_configured`.
- Se confirma el primer candidato válido aunque título o año discrepen; la discrepancia marca `needs_review`. La elección se puede cambiar manualmente o dejar «sin identificar».
- Al confirmar un resultado automático, una transacción bloquea el archivo y la identificación y comprueba token, revisión, disponibilidad y origen. Una corrección manual genera un token nuevo y prevalece ante escaneos, reintentos y respuestas antiguas. La misma transacción reutiliza o crea la obra TMDb y vincula el archivo.
- La escritura de `Movie` se solicita mediante `Catalog.upsert_in_transaction!/2`, con un adaptador detrás del puerto `MovieRepository`. Comparte la transacción abierta por Identificación para que obra y asociación se confirmen juntas. Es una excepción explícita al aislamiento habitual de transacciones entre contextos; la fachada de Catálogo conserva el control de la escritura y el adaptador de Identificación no accede a su repositorio interno.
- La cola de identificación empieza con concurrencia 1 y tres intentos. Los fallos transitorios se reintentan de forma acotada; los permanentes quedan visibles y se pueden solicitar de nuevo. Un reconciliador resuelve trabajos terminales sin resultado.

## Consecuencias

La selección automática prioriza descubrir obras sin bloquear la biblioteca, pero puede asociar una película equivocada. La cola de revisión y la corrección manual son parte necesaria del flujo. Enviar títulos a TMDb revela una parte del nombre de los archivos al proveedor; esta cesión fue aprobada expresamente. Las imágenes de TMDb se solicitan por HTTPS desde el navegador al mostrar una ficha o tarjeta con imagen y pueden revelar al proveedor la IP del cliente y el identificador de imagen. La aplicación conserva un fondo alternativo si no hay imagen.

La unicidad de obra evita duplicar películas para varias versiones. El outbox añade estado y procesos, a cambio de recuperar peticiones confirmadas aunque el proceso caiga antes de encolar. Los originales siguen siendo de solo lectura. Las pruebas locales no acreditan el comportamiento con un token real ni un despliegue en QNAP.

## Referencias

- [Especificación H3](../designs/2026-10-06-h3-catalog-identification-design.md)
- [Plan H3](../plans/h3-catalog-identification.md)
- [Atribución oficial de TMDb](https://developer.themoviedb.org/docs/faq)
- [Logotipos aprobados de TMDb](https://www.themoviedb.org/about/logos-attribution)
