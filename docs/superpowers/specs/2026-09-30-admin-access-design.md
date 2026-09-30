# H1: cuenta administradora y acceso inicial

Estado: diseño aprobado en conversación el 2026-09-30; pendiente de revisión del documento por el propietario. No es un plan de implementación.

## Propósito y alcance

H1 permite crear la cuenta administradora inicial desde la web, iniciar sesión desde móvil u ordenador, ver una pantalla Inicio protegida y cerrar sesión. Deja preparada una identidad real por usuario para las futuras bibliotecas y la actividad personal. No incorpora catálogo, registro de cuentas adicionales, recuperación de contraseña, emparejamiento de televisión ni acceso remoto.

La instalación actual se usa por HTTP en una LAN. El propietario acepta este límite para H1. Contraseñas y cookies viajan sin cifrado en esa red; antes de habilitar acceso remoto habrá que añadir HTTPS y revisar la configuración de cookies y red. Esta aceptación no demuestra que la LAN sea segura frente a observadores o dispositivos comprometidos.

## Decisiones tomadas

- **Alta inicial:** `/setup` muestra un formulario público solo mientras no existe un administrador. El primer alta válida gana; no se pide código de instalación ni acceso SSH. Hay una ventana durante la cual otra persona con acceso a la página podría apropiarse de la instalación. El procedimiento de despliegue indicará al propietario que complete el alta inmediatamente.
- **Identidad:** nombre real, correo normalizado y contraseña. El correo identifica la cuenta para iniciar sesión y es único. El usuario tiene un identificador interno independiente del correo y el rol inicial de administrador.
- **Contraseña:** se guarda únicamente un hash adaptativo con sal, mediante bcrypt. La validación exige una contraseña suficientemente larga y compatible con el límite efectivo de bcrypt; el formulario pide confirmación para reducir errores de primera configuración. No se guardan ni registran contraseñas en claro.
- **Recuperación:** H1 no incluye restablecimiento de contraseña. La recuperación queda anotada como trabajo posterior en el roadmap. Perder la contraseña puede impedir el acceso hasta implementar ese trabajo; la copia de seguridad de PostgreSQL no la revela.
- **Sesión:** dura 30 días desde su creación, sin extensión por actividad. Cada navegador recibe un token aleatorio distinto; PostgreSQL guarda solo su hash. Cerrar sesión revoca el token de ese navegador. Caducidad y revocación se verifican al resolver la sesión. No hay opción «recordarme» ni cierre global de todos los dispositivos en H1.

## Contexto de identidad y persistencia

El contexto `Identity` ofrece una fachada para instalar el primer administrador, autenticar credenciales, crear y resolver sesiones, revocar la sesión actual y autorizar un actor. Las operaciones públicas devuelven resultados o motivos estables, sin schemas Ecto. Los casos de uso reciben puertos concretos; el dominio contiene la identidad y reglas sin depender de Phoenix o Ecto. Los adaptadores Ecto conservan usuarios y sesiones, y convierten explícitamente entre filas y entidades.

La base de datos protege correo único y la unicidad del administrador inicial. La operación de instalación consulta el estado y escribe dentro de una transacción; la restricción de unicidad resuelve carreras entre solicitudes, devolviendo `setup_closed` al perdedor. Un error de validación no cierra la instalación. Tras crear el administrador, toda petición a `/setup`, incluso con un formulario antiguo, se redirige al acceso y no puede crear otra cuenta. No existe un endpoint de registro general. Las altas posteriores requerirán un caso de uso distinto cuando se diseñen varias cuentas.

La verificación de contraseña usa una ruta equivalente para correo desconocido y contraseña errónea, y la interfaz muestra el mismo mensaje genérico. El contexto no revela la existencia de una cuenta por el resultado del formulario de acceso. El hash de contraseña y los tokens se excluyen de respuestas, inspección y logs. Una sesión caducada o revocada no produce un actor.

## Web y flujo

- `/setup`: LiveView de configuración inicial con nombre, correo, contraseña y confirmación. Utiliza un modelo de formulario de presentación, `to_form/2`, `<.form>` y `<.input>`, y reducers de inicialización, validación y envío. Al completar el alta, dirige a `/login` para entrar con las credenciales elegidas.
- `/login`: LiveView de acceso con correo y contraseña y un formulario de presentación. El envío por POST llega a un controller que autentica, establece la sesión HTTP, renueva el identificador de sesión y redirige a Inicio. Ante credenciales incorrectas vuelve al formulario con una indicación genérica. El formulario y los reducers no acceden a schemas de persistencia ni conservan la contraseña en el socket.
- `/`: LiveView Inicio protegida. Muestra la identidad del administrador, una bienvenida y el siguiente paso hacia bibliotecas sin tarjetas ni datos ficticios. Un control visible de cierre de sesión hace una petición protegida que revoca el token actual, borra la cookie y redirige a `/login`.

El router distingue rutas públicas y protegidas. Un plug resuelve la sesión y asigna `current_scope`; el `live_session` protegido también la exige al montar y reconectar la LiveView. `current_scope` contiene un actor obtenido de un token verificado, nunca un identificador enviado por el cliente. Los futuros casos de uso protegidos reciben ese actor y aplican sus propias reglas de autorización, también para acciones iniciadas desde LiveView. La verificación de sesión no concede por sí sola acceso a bibliotecas o medios.

Los templates LiveView comienzan con `<Layouts.app flash={@flash} current_scope={@current_scope}>`. Las pantallas usan la dirección cálida y oscura aprobada para la primera versión, con tipografía legible, foco visible, controles táctiles cómodos y estados de carga y error claros. H1 se diseña para móvil y ordenador. El acceso a la televisión se resolverá mediante emparejamiento en H4.

## Fallos y límites

Un fallo de base de datos al instalar, entrar o resolver una sesión presenta un error genérico al usuario y se registra con motivo seguro, sin credenciales. Si el almacenamiento de sesión falla, la ruta protegida no se concede. Una sesión expirada redirige a `/login`. Cerrar sesión desde una pestaña no debe dejar esa misma sesión reutilizable por otra pestaña al recargar o ejecutar una acción protegida. Los casos de uso futuros deben revalidar la autorización en el servidor.

El HTTP local permite observación o modificación del tráfico dentro de la red; las cookies no podrán marcarse `Secure` mientras se use así. No se publicará el acceso fuera de la LAN con esta configuración. El límite y la migración a HTTPS se documentarán en el procedimiento de despliegue.

## Verificación y aceptación

- Una instalación vacía ofrece `/setup`; la primera solicitud válida crea exactamente un administrador con identidad real. Repetirla o enviarla a la vez desde dos clientes no crea un segundo administrador.
- Una instalación con administrador no ofrece registro público ni permite apropiarse de `/setup`.
- Las credenciales válidas inician sesión; las inválidas producen un mensaje genérico y no crean sesión.
- Una visita anónima o con token vencido o revocado no accede a Inicio. Una sesión válida lo muestra con la identidad correcta.
- Cerrar sesión revoca únicamente el token actual; otra sesión del mismo usuario permanece válida. Una sesión nueva caduca tras 30 días.
- Los formularios, reducers y rutas siguen las convenciones del frontend; la fachada, dominio, puertos y adaptadores siguen las del backend.
- Las pruebas del contexto, persistencia, controller y LiveViews comprueban estos resultados observables. `mix precommit` pasa antes de marcar H1 terminado.
- La documentación de despliegue explica el primer alta, el riesgo del formulario abierto y el límite de HTTP en LAN. No se afirmará compatibilidad de televisión o despliegue HTTPS sin comprobarlos.

## Referencias

- [Encargo H1](../../plans/first-milestone.md)
- [Experiencia aprobada](2026-09-30-first-version-experience-design.md)
- [Arquitectura backend](../../conventions/backend.md) y [frontend](../../conventions/frontend.md)
- [Phoenix `phx.gen.auth`](https://phoenix.hexdocs.pm/mix_phx_gen_auth.html): referencia para tokens y sesión; su registro y enlaces por correo no definen este flujo.
- [OWASP: Transport Layer Security](https://cheatsheetseries.owasp.org/cheatsheets/Transport_Layer_Security_Cheat_Sheet.html): fundamento para exigir HTTPS antes del acceso remoto.
