# H3: catálogo e identificación de películas

Estado: especificación aprobada por el propietario el 2026-10-07. No es un plan de implementación.

## Propósito y alcance

Bolognesa debe convertir el inventario físico de películas en un catálogo que permita encontrar una obra y corregir una identificación errónea. El propietario aceptó enviar a TMDb títulos inferidos de los nombres de archivo para identificarlos automáticamente. Cuando la búsqueda devuelva resultados válidos, Bolognesa elegirá el primero, incluso si la coincidencia parece dudosa, y dejará visible su origen y la necesidad de revisión. El administrador podrá corregirla; ninguna repetición, reintento ni trabajo anterior podrá sustituir su decisión manual.

H3 cubre películas, varias versiones físicas de una obra, resultados dudosos o ausentes, proveedor temporalmente indisponible y corrección manual. La reproducción y el progreso pertenecen a H4. Los originales siguen siendo de solo lectura. La interfaz de exploración sigue la experiencia de la primera versión: móvil y ordenador ahora, con objetivos grandes y alternativa a las imágenes para la futura comprobación en Hisense.

H2c se está validando en otra sesión. H3 puede diseñarse e implementarse sobre el inventario local existente, pero su cierre no atribuye a H2c resultados del NAS que aún no estén registrados.

## Límites y modelo

`Bibliotecas` controla `MediaFile`, su identidad `(library_id, relative_path)` y disponibilidad. `Catálogo` controla `Movie`, con ID interno estable, referencia de proveedor única `(provider, provider_id)`, título, título original, año o fecha cuando exista, sinopsis e identificadores de imagen normalizados. Una obra puede permanecer en catálogo sin archivos disponibles y puede tener varios archivos asociados.

`Identificación` controla una fila por `media_file_id`: estado, `movie_id` opcional, origen `automatic` o `manual`, revisión del archivo observada, token de solicitud y datos acotados de candidatos o duda. Su relación confirmada es la única fuente de verdad entre archivo y obra; `Bibliotecas` y `Catálogo` no guardan otra asociación. Las referencias entre contextos usan IDs y fachadas; las consultas cruzadas para las pantallas se encapsulan en adaptadores de lectura. Las escrituras de películas y de identificación que deban ser atómicas se coordinan mediante un puerto de transacción, sin exponer schemas Ecto al dominio.

Un archivo puede estar pendiente, vinculado automáticamente, vinculado manualmente, declarado manualmente sin identificar o fallido. Un archivo sin coincidencias queda pendiente de revisión. Una selección manual de «sin identificar» impide también futuros vínculos automáticos. La disponibilidad física no borra películas ni decisiones; la pantalla muestra si alguna versión puede utilizarse.

## Solicitud e identificación automática

El guardado de un lote de inventario crea una señal duradera de identificación para archivos nuevos, restaurados o con revisión cambiada, en la misma transacción que sus datos físicos. Un escaneo idéntico no crea otra señal. La señal contiene IDs y revisión, nunca rutas. Un despachador entrega trabajos Oban con concurrencia inicialmente 1 y reintentos acotados. Los archivos inventariados antes de H3 se incorporan por lotes mediante una operación idempotente que crea solicitudes duraderas sin bloquear el arranque ni cargar toda la biblioteca en memoria.

El caso de uso obtiene la ruta relativa por una lectura interna autorizada, usa solo el nombre base para inferir un título y un año cuando sea inequívoco, y consulta TMDb. No envía la ruta completa, nombre de biblioteca, hash ni contenido del vídeo. Los nombres no UTF-8 o sin título utilizable quedan pendientes de revisión sin transformarse silenciosamente. El adaptador de TMDb normaliza y limita la respuesta antes de entregarla a la aplicación; el dominio no depende de Req ni del formato JSON externo.

La búsqueda usa español y excluye resultados marcados para adultos en esta primera versión. Si TMDb devuelve resultados, se selecciona el primer candidato con ID y título válidos. La marca «revisar» se calcula con reglas transparentes y conservadoras, por ejemplo año incompatible o título normalizado muy distinto; no bloquea la elección solicitada por el propietario. Se conserva un conjunto pequeño y acotado de candidatos normalizados para mostrar alternativas, no la respuesta completa del proveedor. Si varias versiones eligen el mismo ID de TMDb, reutilizan la misma `Movie` mediante la restricción única. La ficha detallada se obtiene y normaliza antes de confirmar la vinculación; una respuesta incompleta admite campos opcionales nulos sin inventarlos.

Antes de guardar un resultado, una transacción bloquea la identificación y comprueba el token vigente, la revisión observada y la disponibilidad. Si hubo una decisión manual, descarta el resultado automático aunque el trabajo empezara antes. Los trabajos repetidos o antiguos no crean obras duplicadas ni degradan una vinculación vigente. Una revisión física nueva puede solicitar otra búsqueda para decisiones automáticas, pero conserva las decisiones manuales. No se mantiene ninguna transacción abierta durante HTTP.

## Proveedor, fallos y secretos

Se usará la API v3 de TMDb tras un puerto de búsqueda y detalle, con Req, HTTPS y token de lectura enviado en cabecera. El token se configura en tiempo de ejecución fuera del repositorio y no aparece en logs, errores ni jobs. Sin token, la aplicación arranca y muestra identificación no configurada; no fabrica coincidencias. Las pruebas automatizadas usan un proveedor controlado, no dependen de Internet ni de una cuenta TMDb.

Las llamadas tienen tiempos límite y tamaño de respuesta acotado. Un 429, 5xx o fallo de red se reintenta con demora limitada; los intentos agotados quedan visibles y permiten reintento explícito. Un 401/403, respuesta inválida o ID inexistente queda como fallo visible con motivo seguro. Una búsqueda vacía queda pendiente de revisión, sin reintentos indefinidos. Ningún fallo del proveedor elimina una obra o decisión anterior. Los logs y argumentos de Oban usan IDs, duración, intento y motivos acotados, sin nombres privados, consultas, cuerpos HTTP ni credenciales.

TMDb requiere atribución visible con su aviso y logotipo aprobado en una sección «Acerca de». Las imágenes se referencian mediante identificadores de ruta validados y base HTTPS de TMDb; la interfaz ofrece fondo alternativo cuando no hay imagen o esta no carga. Se revisarán los requisitos vigentes del proveedor al implementar. Referencias: [flujo de búsqueda y detalle](https://developer.themoviedb.org/docs/search-and-query-for-details), [autenticación](https://developer.themoviedb.org/docs/authentication-application), [límites](https://developer.themoviedb.org/docs/rate-limiting) y [atribución](https://developer.themoviedb.org/docs/faq).

## Interfaz y recorrido

La ruta autenticada «Películas» presenta obras agrupadas, estado de disponibilidad y número de versiones. Una sección de revisión presenta archivos sin coincidencia, fallidos o con asociación automática marcada como dudosa. La ficha de obra muestra metadatos, procedencia de la identificación y versiones disponibles; H3 no muestra todavía un botón de reproducción funcional. Una búsqueda dentro del catálogo permite encontrar obras persistidas.

Desde una versión, el administrador puede buscar libremente en TMDb, examinar candidatos y elegir otra obra o «sin identificar». La acción se confirma mediante una llamada autorizada al caso de uso y actualiza catálogo, ficha y revisión. El formulario usa `to_form` y componentes existentes; las colecciones usan streams. Hay estados distintos de carga, vacío y error, con feedback de reintento. La navegación esencial funciona con ratón, tacto y teclado, sin depender de hover. La prueba real en Hisense se registra aparte cuando llegue el recorrido correspondiente.

## Verificación y criterios de aceptación

1. Un archivo nuevo genera una solicitud duradera; un escaneo idéntico no duplica solicitudes; los archivos anteriores a H3 entran por lotes. La fuente de medios sigue de solo lectura.
2. El primer resultado válido se vincula automáticamente; la falta de resultados, título utilizable o proveedor produce un estado visible. Una coincidencia dudosa queda marcada para revisión sin impedir el vínculo automático.
3. Dos archivos identificados con el mismo ID de TMDb comparten `Movie`; ausencia o restauración de un archivo no destruye la obra ni una corrección manual.
4. Una corrección manual y «sin identificar» sobreviven a reescaneos, reintentos y resultados automáticos tardíos. La carrera se comprueba con PostgreSQL real.
5. Fallos y respuestas malformadas del proveedor no revelan secretos o nombres privados ni borran datos válidos. Se comprueban límites, reintentos y recuperación de trabajos con adaptadores controlados.
6. LiveViewTest cubre catálogo, revisión, búsqueda, corrección, autorización, carga, vacío y error mediante selectores estables. Las pruebas relevantes, `mix precommit`, `mix assets.build` y `git diff --check` pasan antes de considerar implementado H3.
7. La integración real se valida posteriormente con token configurado y respuestas agregadas, sin incorporar credenciales o inventarios privados al repositorio. No se declara compatibilidad de TV por las pruebas automatizadas.

## Secuencia de trabajo

El plan de implementación dividirá H3 en entregas verificables: modelo y persistencia, solicitudes y trabajos duraderos, adaptador TMDb, reglas de identificación y corrección, y pantallas. Cada entrega se apoya en contratos y pruebas de comportamiento antes de ampliar la siguiente. La aprobación de esta especificación precede a la redacción del plan.
