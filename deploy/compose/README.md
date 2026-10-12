# Despliegue Linux con Docker Compose

Este despliegue ejecuta Bolognesa y PostgreSQL en un servidor Linux, con HTTP privado por LAN/Tailscale. Los mismos comandos funcionan en el servidor o desde otra máquina por SSH. No abras el puerto en el router ni uses acceso público para este perfil.

## Requisitos

- Docker Engine y Docker Compose **2.24.4 o posterior** en el servidor. Los overrides utilizan [las reglas de sustitución de Compose](https://docs.docker.com/reference/compose-file/merge/).
- `curl`, shell POSIX y `openssl` en el servidor; Bash y Make en la máquina de operación.
- Para SSH: claves configuradas y acceso Docker desde el usuario remoto. No se requieren Python ni jq en el servidor.
- Para `deploy-release`: Git y `gh` autenticado en la máquina de operación, y acceso de descarga a GHCR desde el servidor.
- Carpetas multimedia existentes y legibles para el contenedor, que ejecuta la app como `nobody`.

El puerto se enlaza a loopback por defecto. Para acceso desde otros dispositivos, elige la IP privada LAN o Tailscale en `BOLOGNESA_BIND_IP`. Para escuchar en ambas interfaces mediante `0.0.0.0`, configura filtrado adecuado: los puertos Docker publicados pueden eludir reglas habituales de UFW/firewalld ([documentación de Docker](https://docs.docker.com/engine/install/ubuntu/#firewall-limitations)). HTTP no cifra credenciales ni cookies de aplicación; Tailscale protege el tráfico dentro de su túnel.

## Configuración y primera instalación

Desde la raíz del repositorio:

```sh
cp deploy/compose/deploy.env.example .env.deploy
chmod 600 .env.deploy
```

`.env.deploy` es configuración Make del operador, no un archivo shell ni el `.env` runtime. Usa asignaciones `VARIABLE=valor`, sin comillas envolventes. Puedes cambiar de instalación con `DEPLOY_CONFIG=/ruta/configuracion`; los valores de la línea de comandos de Make tienen prioridad.

Configura `DEPLOY_TRANSPORT=local` para operar en este servidor o `ssh` para otro servidor. En SSH, indica `DEPLOY_HOST=user@server.local`, `DEPLOY_DIR`, `DOCKER_BIN` y `DEPLOY_HEALTH_URL`. La URL debe ser accesible **desde el servidor** y responder satisfactoriamente después de arrancar la app. Las rutas con espacios se admiten. `DOCKER_BIN` es un ejecutable, no un comando con argumentos.

```sh
make deploy-init
```

El comando distribuye las recetas seleccionadas y los scripts, prepara el directorio y genera secretos si no existe `.env`. No sobrescribe los secretos de una instalación existente. Edita el `.env` **en el destino** antes de instalar: `PHX_HOST`, `BOLOGNESA_BIND_IP`, `MEDIA_PATH`, imagen y puerto. Los secretos deben permanecer privados; puedes generarlos manualmente con `openssl rand -hex 64` para Phoenix y `openssl rand -hex 32` para PostgreSQL. El formato hexadecimal evita caracteres reservados en `DATABASE_URL`.

Preflight comprueba espacio disponible para imágenes y backups: `DEPLOY_MIN_FREE_KIB` configura el presupuesto mínimo (predeterminado `262144`, 256 MiB). Ajusta ese presupuesto al tamaño real de la base; no garantiza que cualquier backup quepa. La carpeta PostgreSQL puede seguir privada y pertenecer a PostgreSQL: el usuario SSH no necesita leerla.

Conserva `PUBLIC_PORT` y `BOLOGNESA_PORT` iguales para HTTP directo. `PHX_HOST` es el nombre/IP usado en el navegador. Si utilizas varios nombres privados, `PHX_CHECK_ORIGIN=conn` permite esos orígenes conservando la validación WebSocket; vacío valida contra `PHX_HOST`.

```sh
make deploy-preflight
make deploy-install
```

Install exige que no exista ya el servicio PostgreSQL de ese proyecto. Descarga la imagen, espera DB healthy, crea un backup, aplica migraciones, inicia la app y verifica HTTP. Abre `http://<PHX_HOST>:<PUBLIC_PORT>/setup` para crear la cuenta administradora. El token `TMDB_READ_TOKEN` es opcional para arrancar y necesario para identificar automáticamente obras.

## Red, persistencia y bibliotecas

La receta `compose.yaml` usa red bridge y volumen Docker. `DEPLOY_COMPOSE_FILES` permite agregar archivos **en orden**, separados por `:`. Los archivos relativos se buscan en `deploy/compose/`; `DEPLOY_SOURCE_DIR` permite cambiar ese directorio. Los archivos seleccionados se distribuyen al destino usando sus basenames, que deben ser únicos. No uses `:` dentro de un nombre de archivo.

| Opción | Archivos/configuración |
| --- | --- |
| Bridge + volumen Docker | `DEPLOY_COMPOSE_FILES=compose.yaml` (o agregar `network.bridge.yaml`). DB no publica puertos. |
| Red host | Agregar `network.host.yaml`. Configura `DB_PORT` y el bind/puerto de Phoenix. PostgreSQL escucha exclusivamente en loopback. No se usan mapeos `ports`. |
| Directorio PostgreSQL | Agregar `storage.bind.yaml` y configurar `POSTGRES_DATA_PATH` en `.env`. Crear/verificar ese directorio explícitamente; no se crea al montar. |
| Varias carpetas multimedia | Copiar `media.example.yaml` a `media.local.yaml`, editar los montajes y agregar ese archivo. Mantener todas las fuentes de solo lectura y configurar las raíces internas autorizadas. |

Ejemplo operativo con host networking, base en directorio y varias fuentes:

```make
DEPLOY_COMPOSE_FILES=compose.yaml:network.host.yaml:storage.bind.yaml:media.local.yaml
```

El ejemplo de medios monta `/media/movies` y `/media/series`; puedes agregar cualquier número de fuentes. Registra las rutas **internas** en Bibliotecas. `BOLOGNESA_LIBRARY_ROOTS` debe corresponder a los montajes, separando raíces con `:`. Cambiar las rutas internas de una biblioteca existente puede hacer inaccesibles sus archivos; consérvalas al adoptar este sistema.

`COMPOSE_PROJECT_NAME` identifica contenedores y volumen Docker. No cambies su valor para actualizar una instalación: otro nombre corresponde a otro proyecto y otros datos.

## Imágenes y releases

`.github/workflows/container-image.yml` publica en el namespace GHCR del repositorio GitHub, convertido a minúsculas. En este repositorio es `ghcr.io/avillen/bolognesa`. Publica variantes multi-arquitectura `linux/amd64` y `linux/arm64`: HTTP privado (`latest-lan` / `sha-<commit>-lan`) y HTTPS (`latest` / `sha-<commit>`). Los builds de cada arquitectura y variante se ejecutan en paralelo en runners nativos y se unen en un manifiesto verificado. Este perfil necesita la **variante HTTP**; Docker selecciona la arquitectura del servidor.

La publicación y el despliegue HTTP en el servidor real están verificados. La consulta anónima a GHCR devolvió HTTP 401: para descargar este paquete actualmente necesitas autenticar Docker en el destino con permiso de lectura de paquetes (`read:packages`) o usar una imagen de tu propio registro/build local. El mantenedor debe configurar visibilidad pública del paquete para permitir instalaciones anónimas. Puedes fijar `BOLOGNESA_IMAGE` a un digest o tag inmutable.

```sh
make deploy-release
# O seleccionar el SHA completo de un commit main publicado:
make deploy-release COMMIT_SHA=<40-caracteres-hexadecimales>
```

Release espera el run de CI, comprueba SHA/rama/conclusión y el artefacto `server-image-ref`, y despliega su digest HTTP. Si existen runs repetidos, selecciona `DEPLOY_RUN_ID` explícitamente; la validación de SHA y rama sigue activa. Los artefactos caducan a los 30 días. Para un digest ya verificado:

```sh
make deploy-update IMAGE_REF=ghcr.io/avillen/bolognesa@sha256:<digest>
```

Para forks u otro registro, configura `IMAGE_REPOSITORY`; la operación con un digest explícito admite la referencia elegida por el operador. `DEPLOY_WORKFLOW` y `DEPLOY_ARTIFACT` son configurables.

## Backup, actualización y recuperación

```sh
make deploy-backup
make deploy-update
make deploy-restore BACKUP_FILE=/ruta/del/servidor/backups/archivo.dump
```

Los backups quedan en `<DEPLOY_DIR>/backups` salvo `DEPLOY_BACKUP_DIR`. Cópialos también fuera del servidor. Se valida que el dump no esté vacío y que PostgreSQL pueda leer su índice antes de publicarlo con permisos privados.

Update exige una base existente. Adquiere la imagen antes de detener la app, espera DB healthy, detiene la app, crea backup y referencia anterior, migra, recrea la app y verifica HTTP. Solo después persiste la imagen nueva en el `.env` del destino.

Si falla antes de comenzar migraciones, intenta reactivar la imagen anterior. Si falla desde el comienzo de una migración, deja la app detenida: inspecciona esquema y backup antes de recuperar. Volver a una imagen antigua no revierte migraciones.

La configuración de PostgreSQL queda registrada en `.database-config`. Un cambio de esa configuración o una instalación antigua sin ese registro bloquea la actualización. Después de comparar la receta resuelta con el almacenamiento real, adopta el cambio explícitamente:

```sh
make deploy-update ALLOW_DATABASE_CONFIG_CHANGE=yes EXPECTED_DATABASE_SOURCE=/ruta/postgres
```

Para un volumen Docker, `EXPECTED_DATABASE_SOURCE` es el nombre del volumen existente. Este permiso también cubre cambios deliberados de recursos/red de DB; no lo dejes activado permanentemente. No sustituye la comprobación de que la receta nueva apunta a los mismos datos.

Restore valida el dump, pide escribir `RESTORE` y sustituye la base. La app queda detenida; elige una imagen compatible con el esquema restaurado antes de arrancarla. El script directo acepta `--yes` para automatización explícita. No uses `down -v` para recuperar o actualizar una instalación real.

## Build local y operación diaria

```sh
make deploy-build DEPLOY_BUILD_PLATFORM=linux/arm64 DEPLOY_IMAGE_TAR=/tmp/bolognesa-image.tar
make deploy-upload DEPLOY_IMAGE_TAR=/tmp/bolognesa-image.tar
make deploy-update IMAGE_REF=bolognesa:lan
```

`deploy-upload` también carga el tar en Docker cuando se configura `DEPLOY_IMAGE_TAR`. `DEPLOY_IMAGE_NAME` elige la etiqueta exportada y `BUILD_DOCKER_BIN` el Docker local de construcción (predeterminado `docker`). La construcción ocurre en la máquina de operación; se requiere Buildx y capacidad de construir la plataforma elegida. No fijes plataforma para la imagen multi-arquitectura publicada salvo que quieras elegirla explícitamente.

```sh
make deploy-status
make deploy-logs
make deploy-console
make deploy-psql
make deploy-stop
```

La consola usa la instancia activa de la release. `deploy-stop` conserva datos y contenedores. Para usar scripts directamente en el servidor, configura `DEPLOY_DIR`, `DOCKER_BIN`, `COMPOSE_FILE` y `DEPLOY_HEALTH_URL`, y ejecuta `scripts/operate.sh` con la operación deseada.

## Presupuestos configurables

| Variable runtime | Predeterminado |
| --- | --- |
| `APP_MEMORY_LIMIT` / `APP_CPUS` | `1024m` / `2.0` |
| `DB_MEMORY_LIMIT` / `DB_CPUS` | `256m` / `1.0` |
| `TRANSCODE_TMPFS_SIZE` | `512m` |
| `POOL_SIZE` | `10` |
| `ERL_FLAGS` | Vacío; configurable, por ejemplo `+S 2:2`. |
| `LOG_MAX_SIZE` / `LOG_MAX_FILES` | `10m` / `3` |

Son presupuestos iniciales configurables, no requisitos mínimos ni capacidad medida. La memoria del contenedor incluye Phoenix, FFmpeg y tmpfs; observa consumo y reinicios durante uso real.
