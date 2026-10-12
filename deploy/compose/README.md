# Despliegue genérico en Linux con Docker Compose

Este perfil ejecuta Bolognesa y PostgreSQL en un único servidor Linux con Docker Compose v2. La imagen publicada admite `linux/amd64` y `linux/arm64`; Docker selecciona la plataforma adecuada. Este procedimiento no depende de QNAP.

El servicio web se enlaza a `127.0.0.1` y la imagen aplica HTTPS. Colócalo detrás de un proxy inverso con TLS. No publiques el puerto 4000 directamente en Internet ni habilites HTTP directo: ese modo pertenece al perfil LAN de QNAP.

## Requisitos

- Linux con Docker Engine y el plugin Docker Compose v2.
- Proxy inverso en el servidor, con un nombre DNS y TLS configurados.
- Acceso de lectura del usuario Docker a la carpeta multimedia.
- `openssl` para generar secretos.
- Una imagen genérica publicada en GHCR. El paquete debe permitir descarga anónima. Fija una etiqueta `sha-<commit>` o digest para actualizaciones controladas.

## Imagen publicada

`.github/workflows/container-image.yml` valida el Compose genérico en pull requests y publica la imagen en GHCR desde `main`. La etiqueta `latest` sigue el commit publicado más reciente; cada ejecución también registra una referencia `sha-<commit>` y el digest multi-arquitectura (`linux/amd64` y `linux/arm64`). La imagen genérica conserva HTTPS forzado. El workflow `arm64-image.yml` sigue publicando por separado la variante LAN HTTP para QNAP.

GHCR puede crear el primer paquete como privado. Antes de ofrecer el despliegue a otras personas, el mantenedor debe habilitar la descarga pública del paquete `bolognesa`; verifica una descarga sin iniciar sesión. En `.env`, usa `latest` para probar el último build o fija `BOLOGNESA_IMAGE` al tag `sha-<commit>` o al digest que muestra el resumen de CI.

## Primera instalación

Desde la raíz del repositorio, prepara los archivos de configuración:

```sh
cd deploy/compose
cp .env.example .env
chmod 600 .env
openssl rand -hex 64
openssl rand -hex 32
```

Guarda el primer valor en `SECRET_KEY_BASE` y el segundo en `POSTGRES_PASSWORD`. Edita también `BOLOGNESA_IMAGE`, `PHX_HOST`, `DATA_ROOT` y `MEDIA_PATH`. Los valores de `PHX_HOST` y `PUBLIC_PORT` deben representar la URL HTTPS pública, normalmente el dominio y `443`. Crea `DATA_ROOT` y su directorio `backups`, y asegúrate de que `MEDIA_PATH` ya existe y es legible. Compose rechazará una ruta de medios inexistente en vez de crear una carpeta vacía.

La aplicación se ejecuta como usuario `nobody`. Comprueba que puede atravesar la ruta de medios y leer sus archivos. El contenedor monta esa carpeta como solo lectura en `/media`; registra `/media` como raíz de una biblioteca en Bolognesa.

Configura el proxy inverso para enviar el tráfico HTTPS a `http://127.0.0.1:4000`, conservar el encabezado `Host` y reenviar `X-Forwarded-Proto: https`. Por ejemplo, con Caddy:

```caddyfile
bolognesa.example.com {
    reverse_proxy 127.0.0.1:4000
}
```

Cambia el dominio por el valor real de `PHX_HOST`. Si el proxy usa varios nombres de origen de WebSocket, configura `PHX_CHECK_ORIGIN=conn` en `.env`; por defecto Phoenix sigue validando el origen contra el host configurado.

Inicia la base, ejecuta las migraciones y levanta la app:

```sh
docker compose --env-file .env -f compose.yaml pull
docker compose --env-file .env -f compose.yaml up -d --wait db
docker compose --env-file .env -f compose.yaml run --rm --no-deps app /app/bin/migrate
docker compose --env-file .env -f compose.yaml up -d app
docker compose --env-file .env -f compose.yaml ps
```

Abre `https://<PHX_HOST>`. El primer acceso lleva a `/setup` para crear la cuenta administradora. `TMDB_READ_TOKEN` es opcional para arrancar; se necesita para identificar automáticamente películas y series.

## Copias de seguridad y actualizaciones

La base usa un volumen Docker persistente. Guarda los backups en otra carpeta del host y cópialos también al sistema de backup que uses. Con los valores de ejemplo:

```sh
backup_dir=/srv/bolognesa/backups
mkdir -p "$backup_dir"
docker compose --env-file .env -f compose.yaml stop app
backup_file="$backup_dir/pre-migration-$(date +%Y%m%d-%H%M%S).dump"
docker compose --env-file .env -f compose.yaml exec -T db \
  pg_dump -U bolognesa -d bolognesa -Fc > "$backup_file"
test -s "$backup_file"
```

Edita `BOLOGNESA_IMAGE` en `.env` para indicar el tag `sha-<commit>` o digest que vas a instalar. Después:

```sh
docker compose --env-file .env -f compose.yaml pull app
docker compose --env-file .env -f compose.yaml run --rm --no-deps app /app/bin/migrate
docker compose --env-file .env -f compose.yaml up -d --force-recreate app
docker compose --env-file .env -f compose.yaml ps
```

Comprueba la URL HTTPS a través del proxy, que PostgreSQL esté `healthy` y que el montaje de medios siga siendo de solo lectura:

```sh
docker inspect bolognesa-app-1 --format '{{json .Mounts}}'
```

Si la migración falla, mantén la app detenida y conserva el backup y el volumen original. Restaura el backup en la base persistente antes de volver a iniciar la app; después fija `BOLOGNESA_IMAGE` a la imagen anterior y recrea el servicio. Con el backup anterior disponible, la restauración en el volumen existente se realiza así:

```sh
docker compose --env-file .env -f compose.yaml exec -T db dropdb -U bolognesa --if-exists bolognesa
docker compose --env-file .env -f compose.yaml exec -T db createdb -U bolognesa -O bolognesa bolognesa
docker compose --env-file .env -f compose.yaml exec -T db \
  pg_restore -U bolognesa -d bolognesa --no-owner < "$backup_file"
```

`dropdb` elimina la base actual, pero no el volumen Docker. Úsalo solo después de comprobar que el archivo de backup no está vacío y corresponde a esta instalación. No uses `docker compose down -v` para actualizar o recuperar el servicio.

## Configuración

| Variable | Uso |
| --- | --- |
| `BOLOGNESA_IMAGE` | Imagen publicada; preferiblemente una etiqueta inmutable o digest. |
| `SECRET_KEY_BASE` | Secreto Phoenix generado con `openssl rand -hex 64`. |
| `POSTGRES_PASSWORD` | Contraseña PostgreSQL generada con `openssl rand -hex 32`. |
| `PHX_HOST` | Dominio HTTPS atendido por el proxy. |
| `PUBLIC_PORT` | Puerto público incluido en la URL; normalmente `443`. |
| `BOLOGNESA_PORT` | Puerto local del host al que se conecta el proxy; predeterminado `4000`. |
| `DATA_ROOT` | Carpeta del host para backups; PostgreSQL usa un volumen Docker nombrado. |
| `MEDIA_PATH` | Carpeta multimedia existente del host, montada como `/media` read-only. |
| `TMDB_READ_TOKEN` | Token opcional para identificación y metadatos de TMDb. |
| `PHX_CHECK_ORIGIN` | Vacío conserva la validación contra `PHX_HOST`; `conn` permite varios hosts de origen. |

Para consultar logs y detener los servicios:

```sh
docker compose --env-file .env -f compose.yaml logs --tail 100 app db
docker compose --env-file .env -f compose.yaml down
```

`down` conserva el volumen nombrado. Borrar el volumen de PostgreSQL elimina la cuenta, bibliotecas registradas y catálogo; hazlo solo si quieres descartar los datos.

Si ejecutas la restauración en una shell distinta de la que creó el backup, asigna antes `backup_file` a la ruta exacta del dump que vas a restaurar.
