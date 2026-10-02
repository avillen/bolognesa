# 0002. Acceso inicial y sesiones

Estado: aceptada para H1, 2026-10-02.

## Contexto

Bolognesa necesita una identidad administradora real antes de configurar bibliotecas. El despliegue inicial solo es accesible por HTTP en la LAN y no tiene servicio de correo ni recuperación de contraseñas.

## Decisión

- `/setup` queda abierto hasta que se crea el primer administrador. PostgreSQL garantiza un único administrador mediante una restricción parcial, incluso ante solicitudes simultáneas.
- El administrador se identifica mediante nombre y correo ASCII normalizado único. bcrypt guarda el hash de una contraseña de 12 a 72 bytes sin bytes nulos; no se incorpora ninguna credencial al repositorio o al despliegue.
- Cada navegador recibe un token aleatorio distinto. PostgreSQL guarda únicamente su hash SHA-256; la sesión vence a los 30 días desde su creación sin renovación deslizante. Cerrar sesión revoca solo el token actual.
- El servidor resuelve un actor verificado para rutas protegidas y LiveViews. Las operaciones futuras deberán comprobar su propia autorización en el backend.
- El HTTP actual se limita a la LAN y exige HTTPS antes de habilitar acceso remoto. Mientras siga en HTTP, la cookie no se marca `Secure`.

## Consecuencias

Existe una ventana de apropiación antes del primer alta; el propietario debe completarla inmediatamente tras desplegar H1. Las contraseñas y cookies pueden ser observadas o modificadas por quien controle tráfico de la LAN. No hay recuperación de contraseña en H1, por lo que perderla puede bloquear el acceso. El despliegue en QNAP y el comportamiento visual en dispositivos todavía requieren comprobación específica; las pruebas locales no los acreditan.
