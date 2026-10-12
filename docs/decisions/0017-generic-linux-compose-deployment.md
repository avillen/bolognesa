# 0017. Despliegue genérico Linux con Docker Compose

## Estado

Aceptada; ampliada el 2026-10-12 para HTTP privado y un despliegue común configurable. La implementación local admite red bridge/host, base en volumen/directorio y operación local/SSH. Publicación multi-arquitectura y sustitución real del despliegue anterior verificadas; ver evidencia en `docs/validation/qnap.md`.

## Contexto

Bolognesa se inició en un QNAP TS-233, y sus archivos de configuración y operación habían hecho que QNAP pareciera un requisito de la aplicación. La app, sin embargo, usa bibliotecas locales visibles desde el contenedor, PostgreSQL y herramientas Linux comunes. El perfil de QNAP necesita además rutas compartidas, límites y ajustes de red propios, incluido HTTP LAN y acceso privado Tailscale.

El Compose de la raíz sirve para desarrollo local y no es una receta de producción. Hacía falta ofrecer un despliegue Linux genérico sin sustituir ni modificar el procedimiento QNAP que ya se usa.

## Decisión

- Mantener el Compose raíz para desarrollo local.
- Unificar despliegue y operación en `deploy/compose/`, con aplicación y PostgreSQL persistente, opciones de red bridge/host, almacenamiento volumen/bind, bibliotecas y recursos configurables.
- Sustituir el despliegue real existente por la receta común antes de eliminar `deploy/qnap/`, los comandos específicos y el workflow anterior. Conservar rutas internas, secretos y datos; registrar backup y verificaciones reales.
- Montar bibliotecas como solo lectura, no publicar PostgreSQL y enlazar el puerto web a loopback por defecto, con bind configurable para acceso desde interfaces privadas.
- Publicar una imagen segura con HTTPS forzado y otra imagen multi-arquitectura con HTTP para LAN/Tailscale. El perfil Compose genérico usa la variante HTTP en esta fase; el tráfico no se expondrá a Internet.
- Configurar raíces multimedia y origen WebSocket en runtime. Phoenix conserva la validación de origen contra `PHX_HOST` salvo que el operador use explícitamente `PHX_CHECK_ORIGIN=conn` para varios hosts.
- Publicar imágenes genéricas para `linux/amd64` y `linux/arm64`, y documentar pinning por tag de commit o digest.

## Consecuencias

- El código de la aplicación no necesita saber qué fabricante o layout de carpetas usa el host; el operador configura las rutas vistas dentro del contenedor.
- Los scripts y comandos `deploy-*` sirven para operación local o SSH. Las particularidades del servidor son configuración privada; la evidencia histórica sigue en validación QNAP y la traducción está en la guía de transición.
- Cambios en la configuración PostgreSQL requieren adopción explícita y comprobación de la fuente existente. La mayor flexibilidad tiene el coste de elegir correctamente archivos Compose, proyecto y rutas; un update no inicializa silenciosamente una base nueva.
- El acceso HTTP privado no cifra las credenciales ni las cookies de aplicación. La guía limita el uso a redes privadas y no configura firewall ni acceso remoto; la exposición pública requiere la imagen segura y un proxy con TLS.
- La matriz Compose y las pruebas de actualización, transporte y release se comprobaron localmente. Una integración Docker con datos sintéticos verificó instalación, backup, actualización y restauración. La publicación y migración reales se registran separadamente cuando se ejecutan.
