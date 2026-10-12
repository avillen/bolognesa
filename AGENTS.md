# Bolognesa: instrucciones compartidas

Aplicación web Phoenix para aprendizaje y uso doméstico. Las decisiones y convenciones de Bolognesa gobiernan el proyecto. Superpowers y otras herramientas pueden ayudar al proceso, pero deben guardar sus artefactos en la estructura de este repositorio y respetar las instrucciones del usuario.

## Continuidad de sesión

- Al comenzar, leer [producto](docs/product.md), [estado](docs/status.md), [roadmap](docs/roadmap.md) y las convenciones aplicables. Inspeccionar Git y conservar cambios ajenos.
- Elegir una tarea acotada con criterios de aceptación; leer su diseño, plan y [decisiones](docs/decisions/README.md) relevantes. Comprobar el código antes de asumir que existe una función.
- Al terminar trabajo significativo, ejecutar `mix precommit` y los checks pertinentes; corregir fallos y actualizar `docs/status.md` con estado real, verificación, bloqueos y siguiente paso. No atribuir despliegue ni compatibilidad de dispositivos sin evidencia.
- Si queda trabajo incompleto, registrar archivos o rama, pasos pendientes, comando fallido y síntomas reproducibles. No guardar credenciales ni inventarios privados de medios.
- Marcar un hito completo solo al cumplir los criterios de `docs/roadmap.md`. Evitar planes vacíos o implementaciones especulativas.

## Organización documental

- `docs/conventions/`: reglas técnicas vigentes. Actualizar la convención cuando cambie una regla acordada.
- `docs/decisions/`: decisiones relevantes, motivos y costes aceptados; indexarlas en su README.
- `docs/designs/`: comportamiento y contratos acordados, independientes de la herramienta usada para diseñarlos.
- `docs/plans/`: pasos de implementación acotados. Crear planes solo cuando se vayan a ejecutar.
- `docs/validation/`: comprobaciones reales de QNAP, navegadores y dispositivos. Separar observaciones de expectativas.
- `docs/history/`: antecedentes y verificaciones anteriores. `docs/status.md` es una instantánea breve, no un historial.

Si una habilidad sugiere `docs/superpowers/specs/` o `docs/superpowers/plans/`, usar respectivamente `docs/designs/` o `docs/plans/`. No crear directorios por herramienta ni duplicar instrucciones en archivos específicos de un agente.

## Convenciones por área

| Área | Referencia |
| --- | --- |
| Módulos Elixir, APIs públicas y Mix | [Elixir](docs/conventions/elixir.md) |
| Dominio, aplicación, persistencia, integraciones y autorización | [Backend](docs/conventions/backend.md) |
| LiveViews, reducers, forms y estado de vista | [Frontend](docs/conventions/frontend.md) |
| Phoenix 1.8, HEEx, Ecto, Tailwind, hooks e interacción | [Phoenix e interfaz](docs/conventions/phoenix.md) |
| Cambios funcionales, pruebas y refactors | [Testing](docs/conventions/testing.md) |
| Logs, errores y trabajos de fondo | [Observabilidad](docs/conventions/observability.md) |

Leer todas las convenciones aplicables antes de modificar un área. Mantener los planes separados de las reglas duraderas.

## Operación

Antes de desplegar, leer `make help` y [la guía de despliegue común](deploy/compose/README.md). Configurar la instalación con `.env.deploy` y usar `make deploy-release` para un commit `main` publicado. Registrar el run de CI, digest de imagen, backup y verificación reales; conservar proyecto, datos y rutas internas al actualizar.
