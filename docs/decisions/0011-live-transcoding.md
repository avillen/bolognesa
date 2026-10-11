# 0011. Conversión al vuelo para reproducción compatible

Estado: implementada en `main` y desplegada en QNAP el 2026-10-10 mediante el commit `ab628a6`; capacidad real y fluidez en clientes pendientes de comprobar con el propietario.

## Contexto

Chrome mostró imagen sin audio para Matroska/H.264/AC-3 y no pudo abrir una AVI/MPEG-4 Part 2/AC-3 aunque la entrega original respondió `206`. La entrega directa de H4a sigue siendo válida para un MP4/H.264/AAC comprobado. El propietario pidió conversión al vuelo y omitió una prueba previa de capacidad.

## Decisión

- La inspección técnica vigente por revisión selecciona entrega directa, conversión de audio con vídeo H.264 copiado o conversión de vídeo a H.264 y audio a AAC. Si no hay perfil conocido, se prueba la entrega directa y se ofrece un modo compatible manual tras un fallo del navegador.
- FFmpeg genera HLS MPEG-TS en un directorio temporal privado. Un `GenServer` supervisado posee el único proceso FFmpeg permitido; un `DynamicSupervisor` añadiría coordinación sin aportar concurrencia en esta fase. La sesión caduca tras cinco minutos sin actividad, limita los fragmentos a 512 MiB y elimina el directorio al cerrar. El montaje temporal en QNAP es `tmpfs`; la biblioteca original permanece en un montaje de solo lectura.
- El pipeline de medios autentica cada lista y segmento y confirma relación película-archivo, revisión y existencia del original en cada petición. El identificador de sesión no concede acceso. Solo se admiten nombres de segmento generados por la aplicación.
- El cliente usa hls.js 1.7.0 con Media Source Extensions y HLS nativo como alternativa. FFmpeg lee a velocidad de reproducción (`-re`); tras generar el primer segmento queda suspendido hasta que el navegador inicia la reproducción. Pausar suspende FFmpeg y reanudar lo continúa en la misma sesión. Una barra de posición absoluta reinicia FFmpeg al saltar; si la sesión caduca durante la pausa, reanudar crea otra desde la posición visible.

Se evaluó Membrane. Los componentes publicados no cubren directamente esta combinación de AVI/MPEG-4 Part 2/AC-3, por lo que añadirlo ahora complicaría el recorrido sin eliminar la dependencia de códecs externos. FFmpeg ya forma parte de la imagen para inspección.

## Sustitución y cierre de sesiones (2026-10-11)

Una nueva reproducción compatible sustituye atómicamente la sesión anterior del mismo actor, incluso desde otra pestaña. La sesión de otro actor conserva el cupo y devuelve `:busy`. El gestor monitoriza el proceso que inició la sesión y libera FFmpeg y los fragmentos cuando ese proceso termina; el evento `ended` del navegador libera la sesión al acabar el vídeo. Los cinco minutos sin actividad quedan como respaldo. Cerrar una página antigua o recibir eventos de su sesión no detiene la sesión nueva. Este ajuste está implementado localmente; publicación y comprobación en QNAP pendientes.

## Consecuencias

FFmpeg reabre el original por ruta después de la validación con descriptor. Entre ambas operaciones existe una carrera que la API de procesos no hace atómica; el montaje de solo lectura evita modificaciones por Bolognesa, pero no impide cambios externos. HLS añade fragmentos temporales y una dependencia JavaScript. La fluidez, CPU, memoria y compatibilidad de Chrome, móvil e Hisense se comprobarán con la versión desplegada; la prueba sintética local confirma códecs de salida, no capacidad del NAS.

hls.js se distribuye en `assets/vendor/hls.min.mjs` desde `hls.js@1.7.0/dist/hls.min.mjs`, con licencia Apache-2.0 en `assets/vendor/hls.LICENSE`. SHA-256 del módulo: `18f247005b2fd6b97998ceefed4b775f2dc01c088e9a5c38ca6a5ba1a0644f17`.

## Referencias

- [Diseño](../designs/2026-10-10-h4-live-transcoding-design.md)
- [Plan](../plans/2026-10-10-h4-live-transcoding.md)
- [FFmpeg HLS muxer](https://ffmpeg.org/ffmpeg-formats.html)
- [hls.js](https://github.com/video-dev/hls.js)
