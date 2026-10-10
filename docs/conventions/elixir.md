# Convenciones de Elixir

## Contratos públicos

- Declara un `@spec` para cada función pública (`def`) y macro público (`defmacro`). Sitúalo antes de la primera cláusula y cubre con un único contrato todas las cláusulas y argumentos por defecto.
- Usa tipos que expresen las entradas admitidas y los resultados posibles, incluidos los errores. Define `@type` cuando un tipo propio haga el contrato más claro.
- Evita tipos demasiado amplios como `term()` o `module()` en los contratos públicos. Usa tipos de dominio o de puerto con nombre (por ejemplo, `User.id()` o `UserRepository.adapter()`); para una struct, tipa sus campos con esos tipos propios.
- Para dependencias inyectadas como módulos, define un tipo de adaptador en el puerto (por ejemplo, `UserRepository.adapter()`) y úsalo en los specs de los casos de uso. Su representación puede ser `atom()`: los typespecs de Elixir no pueden expresar ni comprobar que un módulo implemente un behaviour. Declara el `@behaviour` en cada adaptador y verifica sus callbacks al compilar; el tipo con nombre comunica el contrato, pero no sustituye esa comprobación.
- Da a los tipos temporales un nombre acorde con su significado: el instante recibido al crear una sesión es `issued_at()`, mientras que `expires_at()` describe el valor calculado y almacenado.
- Los tipos de estructuras reflejan sus etapas reales. Si un ID solo existe tras guardar, usa un tipo distinto para los datos previos y reserva el tipo de la entidad para los valores con ID; no amplíes el campo a `id() | nil` en ambos contratos.
- Las funciones que implementan callbacks de un behaviour no necesitan un `@spec` propio: el contrato está en el `@callback` correspondiente. Marca esas implementaciones con `@impl true` cuando proceda.
- No se exigen specs para funciones privadas (`defp`) ni para funciones generadas por macros o bibliotecas.

## Flujo de control

- No anides condicionales (`if`, `case`, `cond` o `with`) dentro de otros condicionales en una misma función. Extrae la decisión interior a una función privada con un nombre que explique su propósito.
- Haz visible el flujo esperado de la función principal. Separa la validación, los casos de error y los efectos secundarios en pasos pequeños cuando una rama o una función anónima oculte ese recorrido. Conserva las mismas respuestas y efectos al refactorizar.

## Reglas de Elixir y Mix

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
