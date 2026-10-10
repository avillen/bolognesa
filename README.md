# Bolognesa

Mediacenter personal en Elixir y Phoenix, desarrollado por etapas para aprendizaje y uso doméstico.

## Continuar el proyecto

Empieza por [AGENTS.md](AGENTS.md) y el [estado actual](docs/status.md).

- [Producto](docs/product.md): propósito y alcance.
- [Roadmap](docs/roadmap.md): hitos y criterios de aceptación.
- Convenciones de [backend](docs/conventions/backend.md) y [frontend](docs/conventions/frontend.md).
- Convenciones de [testing](docs/conventions/testing.md) y [observabilidad](docs/conventions/observability.md).
- [Decisiones](docs/decisions/README.md): motivos de las elecciones arquitectónicas.
- [Diseños](docs/designs/) y [planes](docs/plans/): alcance acordado y pasos de implementación.
- [Validaciones](docs/validation/) e [historial](docs/history/): pruebas reales y antecedentes.

## Desarrollo local

Necesitas Elixir/Erlang compatibles con `mix.exs` y las dependencias bloqueadas en `mix.lock`, además de PostgreSQL accesible con la configuración de `config/dev.exs` y `config/test.exs`. La base Phoenix está desplegada en el QNAP; consulta el estado para conocer las comprobaciones pendientes.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Run `mix precommit` to compile with warnings as errors, check unused dependencies, format and run the tests. Tests require PostgreSQL.

Para el despliegue QNAP y los comandos para publicar nuevas versiones, ejecuta `make help` y consulta [las instrucciones QNAP](deploy/qnap/README.md).

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
