# 0017. Despliegue genérico Linux con Docker Compose

## Estado

Aceptada e implementada localmente. La publicación multi-arquitectura y el arranque en un servidor Linux genérico siguen pendientes de verificar.

## Contexto

Bolognesa se inició en un QNAP TS-233, y sus archivos de configuración y operación habían hecho que QNAP pareciera un requisito de la aplicación. La app, sin embargo, usa bibliotecas locales visibles desde el contenedor, PostgreSQL y herramientas Linux comunes. El perfil de QNAP necesita además rutas compartidas, límites y ajustes de red propios, incluido HTTP LAN y acceso privado Tailscale.

El Compose de la raíz sirve para desarrollo local y no es una receta de producción. Hacía falta ofrecer un despliegue Linux genérico sin sustituir ni modificar el procedimiento QNAP que ya se usa.

## Decisión

- Mantener el Compose raíz para desarrollo local.
- Mantener el despliegue específico del NAS en `deploy/qnap/`.
- Añadir un perfil autónomo de servidor Linux en `deploy/compose/`, con aplicación y PostgreSQL persistente.
- Montar bibliotecas como solo lectura, no publicar PostgreSQL y enlazar el puerto web a loopback.
- Usar una imagen genérica con HTTPS forzado detrás de un proxy inverso TLS. La imagen LAN HTTP y el acceso Tailscale propios de QNAP permanecen en su perfil.
- Configurar raíces multimedia y origen WebSocket en runtime. Phoenix conserva la validación de origen contra `PHX_HOST` salvo que el operador use explícitamente `PHX_CHECK_ORIGIN=conn` para varios hosts.
- Publicar imágenes genéricas para `linux/amd64` y `linux/arm64`, y documentar pinning por tag de commit o digest.

## Consecuencias

- El código de la aplicación no necesita saber qué fabricante o layout de carpetas usa el host; el operador configura las rutas vistas dentro del contenedor.
- Las instrucciones generales ya no dependen de QNAP. Sus límites de recursos, la configuración de host y la evidencia de uso real siguen en la guía y validación QNAP.
- El servidor necesita un proxy inverso con TLS. Este perfil no configura DNS, certificados, proxy ni acceso remoto.
- La validez del Compose se comprobó localmente. No se ha ejecutado el workflow de publicación ni se ha arrancado el perfil en un servidor Linux genérico; tampoco se ha confirmado la visibilidad pública del paquete GHCR.
