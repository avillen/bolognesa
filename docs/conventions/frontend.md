# Frontend: arquitectura y convenciones

Este documento recoge las convenciones acordadas para la presentación web de Bolognesa. Debe mantenerse actualizado cuando cambien. Complementa las reglas de Phoenix y LiveView de `AGENTS.md` y las [convenciones del backend](backend.md).

## Organización por pantalla

Cada pantalla agrupa su LiveView, template, reducers, modelos de presentación, formularios y componentes específicos. Se crea un archivo por reducer público. Los directorios y módulos se añaden cuando una funcionalidad los necesita, sin generar carpetas vacías por adelantado.

```text
lib/bolognesa_web/live/movie/
  index/
    live.ex
    live.html.heex
    reducers/
      initialize.ex
      apply_filters.ex
      fetch_movies.ex
      apply_movies_result.ex
    state/
      movie.ex
    forms/
      filters.ex
    components/
      movie_card.ex
  show/
    live.ex
    live.html.heex
    reducers/
    state/
    forms/
```

Los módulos siguen la estructura:

| Archivo relativo a `live/movie/` | Módulo |
| --- | --- |
| `index/live.ex` | `BolognesaWeb.Movie.Index.Live` |
| `index/reducers/fetch_movies.ex` | `BolognesaWeb.Movie.Index.Reducers.FetchMovies` |
| `index/state/movie.ex` | `BolognesaWeb.Movie.Index.State.Movie` |
| `index/forms/filters.ex` | `BolognesaWeb.Movie.Index.Forms.Filters` |
| `index/components/movie_card.ex` | `BolognesaWeb.Movie.Index.Components.MovieCard` |

Esta convención específica sustituye para las nuevas pantallas la organización genérica `movie_live/index.ex`. Dentro del scope web, la ruta referencia `Movie.Index.Live`, sin repetir el prefijo `BolognesaWeb`.

## LiveViews y reducers

La LiveView recibe y delega los callbacks de ciclo de vida, parámetros, eventos, mensajes y resultados asíncronos. Devuelve las tuplas requeridas por LiveView. Los reducers coordinan la presentación e invocan las fachadas públicas del backend.

Cada reducer expone `call(socket, ...)`, recibe el socket como primer argumento y devuelve siempre un socket. Los argumentos adicionales contienen los datos necesarios para la operación. Las funciones privadas pueden transformar datos sin recibir un socket.

```elixir
alias BolognesaWeb.Movie.Index.Reducers

def handle_params(params, _uri, socket) do
  socket =
    socket
    |> Reducers.ApplyFilters.call(params)
    |> Reducers.FetchMovies.call()

  {:noreply, socket}
end

def handle_async(:load_movies, result, socket) do
  {:noreply, Reducers.ApplyMoviesResult.call(socket, result)}
end
```

El término reducer describe aquí una operación de presentación sobre el socket; no implica pureza funcional. Puede consultar el backend, actualizar assigns o streams e iniciar efectos propios de LiveView.

- Los reducers contienen coordinación de interfaz, no reglas de negocio ni consultas directas a schemas o repositorios internos del backend.
- Las reglas y la autorización se ejecutan en los casos de uso del backend.
- Un pipeline expresa pasos que pueden ejecutarse consecutivamente. Si un paso depende del éxito de otro, un reducer coordinador trata esa condición explícitamente.
- Un reducer público representa una operación coherente. No se crea un módulo por cada `assign`; sus pasos internos pueden ser funciones privadas.
- Se evita un módulo global de reducers. Las operaciones pertenecen a su pantalla.

## Estado de presentación

El socket es el contenedor del estado de la pantalla. No se introduce un struct paralelo que duplique todos sus assigns y streams.

`state/` contiene modelos de vista específicos, independientes de las entidades del dominio y de los schemas de persistencia. Por ejemplo, `State.Movie` puede contener el identificador, título, imagen, disponibilidad y progreso necesarios para una tarjeta. La conversión desde la respuesta del backend es explícita y no consulta servicios por sí misma.

Los modelos insertados en streams proporcionan una identidad estable. Los templates consumen datos preparados para la vista. No se crea un modelo adicional para cada assign sencillo.

- `assign` se utiliza para filtros, selección, formularios y estados de carga.
- Las colecciones se gestionan con streams y las reglas de DOM indicadas en `AGENTS.md`.
- Los helpers compartidos de streams se extraen a `lib/bolognesa_web/live_support/` cuando exista repetición real.
- Los helpers expresan operaciones concretas, como reiniciar una colección y actualizar su estado vacío. No deciden silenciosamente entre `assign` y `stream`.
- El total de resultados y el número de elementos cargados son conceptos distintos al paginar.
- Un cambio de estado que afecte a la representación de un elemento del stream debe volver a insertar o reiniciar los elementos afectados.

## Formularios

`forms/` contiene modelos y changesets exclusivos de presentación, mediante schemas embebidos sin persistencia o changesets sin schema. Los nombres describen la finalidad: `Forms.Filters`, `Forms.Identification` o `Forms.Movie` cuando exista un formulario de edición de película.

Los changesets comprueban formato, campos obligatorios y coherencia de entrada. El backend valida de nuevo las reglas del dominio. No se exponen schemas Ecto de persistencia a la interfaz.

Los reducers convierten los changesets con `to_form/2` y asignan el resultado al socket. Los templates utilizan `<.form>` y `<.input>` sobre ese formulario, conforme a `AGENTS.md`.

## Cargas, errores y navegación

- Las consultas lentas se ejecutan mediante los mecanismos asíncronos de LiveView. Un reducer inicia la carga y otro aplica el resultado.
- La función asíncrona recibe únicamente los datos necesarios, extraídos antes de iniciarla; no captura el socket completo.
- Las respuestas obsoletas no sustituyen peticiones más recientes. Se identifica la carga vigente y se aplican las garantías de cancelación o descarte del mecanismo utilizado.
- Cargando, vacío y error son estados diferentes. Un fallo de actualización no presenta una colección vacía como resultado correcto.
- Los reducers traducen los resultados del backend a contenido, formularios, estados y feedback de interfaz. También manejan la terminación fallida de las tareas asíncronas.
- Los filtros navegables, búsqueda y orden se representan en la URL y se interpretan desde `handle_params`, de modo que recargar y volver atrás recuperen la vista.
- Los trabajos duraderos, como escanear una biblioteca, pertenecen al backend. LiveView solicita su ejecución y observa el progreso; cerrar la página no los cancela.

## Templates, componentes y navegador

### Notificaciones del backend

La LiveView se suscribe a los topics autorizados cuando está conectada y recibe las notificaciones mediante `handle_info/2`. Delega su tratamiento a un reducer que obtiene el estado actualizado mediante la fachada del backend y modifica la presentación. El frontend no publica los eventos de dominio; solicita acciones mediante los casos de uso.

Al conectar o reconectar se recupera el estado del backend, sin depender de mensajes recibidos anteriormente. Suscribir antes de cargar el estado actualizado evita dejar un intervalo sin observar cambios; el manejo posterior debe tolerar notificaciones duplicadas y recargas concurrentes. Al cambiar el recurso observado se ajustan las suscripciones.

El topic no concede permisos. Tanto la suscripción como las consultas y acciones deben respetar el acceso del usuario. Los resultados de tareas propias de la pantalla se reciben por `handle_async`, separados de las notificaciones PubSub.

### Componentes e interacción

El template principal se mantiene junto a la LiveView. Los componentes reciben atributos y emiten eventos; no consultan el backend. Se prefieren componentes de función y se reserva LiveComponent para necesidades concretas de estado y ciclo de vida propios.

Los componentes específicos viven dentro de la pantalla. Cuando se comparten entre pantallas de películas pueden situarse en `live/movie/components/`; si se reutilizan entre funcionalidades, en `lib/bolognesa_web/components/`. La extracción responde a reutilización o responsabilidades claras.

Todos los templates LiveView comienzan con `<Layouts.app flash={@flash} ...>`, pasando el scope cuando corresponda. Se mantienen las convenciones de formularios, iconos y componentes de `AGENTS.md`.

Los hooks viven en `assets/js/hooks/` y se importan desde `assets/js/app.js`. Los estilos adicionales se importan desde `assets/css/app.css`, conservando la configuración Tailwind existente. No se añaden scripts externos o scripts inline ordinarios a los templates.

El navegador controla el estado inmediato del reproductor, como posición instantánea, volumen y pantalla completa. El hook comunica acciones y progreso relevante; el backend conserva el progreso duradero. No se envía cada actualización visual del vídeo al servidor.

La interfaz debe contemplar ratón, pantalla táctil, teclado y mando: acciones esenciales sin depender de hover, foco visible y orden predecible. Los diálogos y actualizaciones dinámicas deben conservar o restaurar el foco de forma coherente. La navegación con el mando y la reproducción se validarán temprano en la televisión real; no se presupone compatibilidad por usar un navegador. Solo se añadirá navegación personalizada mediante hooks si la nativa resulta insuficiente.

## Verificación

Las pruebas de interacción con LiveViewTest se organizan por pantalla, por ejemplo `test/bolognesa_web/live/movie/index/live_test.exs`. Se utilizan IDs y selectores estables y se comprueban resultados observables.

Se añaden pruebas directas de reducers para transiciones complejas que lo justifiquen, sin duplicar automáticamente las pruebas de interacción. Los modelos de presentación y formularios pueden probarse de forma aislada cuando contengan transformaciones o validaciones relevantes.

Se verifican los estados de carga, error y vacío, las respuestas obsoletas, los formularios y la actualización de streams según las necesidades de cada pantalla. Se aplican las [convenciones de testing](testing.md), priorizando comportamiento sobre detalles internos. Al finalizar cambios se ejecuta `mix precommit`.
