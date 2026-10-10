# 0006. Entrega directa autorizada de archivos

Estado: aceptada para la implementación local de H4a el 2026-10-10; desplegada; reproducción de una versión compatible observada en Chrome, otros formatos y dispositivos pendientes.

## Contexto

P0 comprobó una muestra MP4 pública con rangos en ordenador, móvil e Hisense. H2 inventaría archivos privados y H3 los vincula a películas. H4a necesita entregar el original sin publicar la biblioteca en `Plug.Static`, permitir saltos de posición y rechazar peticiones realizadas después de cerrar o revocar una sesión.

## Decisión

- La ficha permite elegir explícitamente un archivo disponible de la película. El navegador usa `<video>` con controles nativos, sin reproducción automática. El progreso duradero se diseñará por separado.
- Una ruta del mismo origen recibe IDs de película y archivo, nunca una ruta física ni un token en la URL. Resuelve la sesión vigente y vuelve a autorizar la relación actual en cada `GET` y `HEAD`. Sin sesión devuelve `401` vacío, sin redirigir a una página HTML.
- Un pipeline de medios utiliza la cookie de sesión y omite la restricción `Accept: text/html` del pipeline de páginas; así admite las peticiones de vídeo del navegador. La respuesta establece `Cache-Control: private, no-store`.
- El adaptador valida fuente, ruta relativa, ancestros físicos, archivo regular, tamaño, modificación e identidad. Abre el archivo y compara el descriptor con el estado validado; vuelve a comprobar raíz y ancestros después de abrir. El controlador transmite desde ese descriptor por fragmentos de hasta 64 KiB; no usa `send_file`, que reabriría la ruta.
- Se acepta una petición completa (`200`) o un único rango `bytes` (`206`). Sintaxis inválida devuelve `400`; rango no satisfacible, `416` y `Content-Range: bytes */total`. El endpoint conserva el método original antes de que `Plug.Head` lo transforme; `HEAD` envía cabeceras sin leer el contenido. Los tipos MIME proceden de una lista cerrada de extensiones de vídeo.
- Al elegir una versión, una comprobación corta detecta archivos ya ausentes y muestra un error distinto del fallo que comunica el navegador al intentar reproducir el contenido. La petición de contenido vuelve a autorizar y validar: la comprobación previa no concede acceso ni evita una carrera posterior.

## Consecuencias

La ruta autenticada evita credenciales temporales adicionales y permite revocar el acceso para la siguiente petición. Cada rango hace una consulta de autorización y valida el archivo, con coste adicional para PostgreSQL y el NAS. La validación del descriptor evita entregar otro archivo si una ruta cambia antes de abrirlo; el contenido de un archivo ya abierto puede cambiar por acciones externas y no se obtiene una instantánea atómica. Los originales se leen sin modificarlos.

La doble comprobación de ancestros detecta un cambio entre validación y apertura, pero no ofrece una garantía atómica frente a un actor externo que intercambie y restaure un directorio en esa ventana. El montaje de medios es de solo lectura para Bolognesa; no se afirma una defensa absoluta frente a escrituras concurrentes hechas fuera de la aplicación. Una garantía estricta requeriría abrir cada componente relativo a un descriptor de directorio con primitivas del sistema operativo no expuestas por `:file.open/2`.

La entrega de bytes no implica compatibilidad de contenedor o codec. H4a informa de un fallo de navegador y permite elegir otra versión. La compatibilidad de ordenador, móvil e Hisense debe verificarse con la ruta privada y archivos reales. Esta decisión no incluye transcodificación, progreso guardado ni emparejamiento de TV.

## Referencias

- [Diseño H4a](../designs/h4-direct-playback-design.md)
- [Plan H4a](../plans/h4-direct-playback.md)
