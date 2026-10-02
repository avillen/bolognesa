# Convenciones de Elixir

## Contratos públicos

- Declara un `@spec` para cada función pública (`def`) y macro público (`defmacro`). Sitúalo antes de la primera cláusula y cubre con un único contrato todas las cláusulas y argumentos por defecto.
- Usa tipos que expresen las entradas admitidas y los resultados posibles, incluidos los errores. Define `@type` cuando un tipo propio haga el contrato más claro.
- Evita tipos demasiado amplios como `term()` o `module()` en los contratos públicos. Usa tipos de dominio o de puerto con nombre (por ejemplo, `User.id()` o `Repository.adapter()`); para una struct, tipa sus campos con esos tipos propios.
- Para dependencias inyectadas como módulos, define un tipo de adaptador en el puerto (por ejemplo, `Repository.adapter()`) y úsalo en los specs de los casos de uso. Su representación puede ser `atom()`: los typespecs de Elixir no pueden expresar ni comprobar que un módulo implemente un behaviour. Declara el `@behaviour` en cada adaptador y verifica sus callbacks al compilar; el tipo con nombre comunica el contrato, pero no sustituye esa comprobación.
- Da a los tipos temporales un nombre acorde con su significado: el instante recibido al crear una sesión es `issued_at()`, mientras que `expires_at()` describe el valor calculado y almacenado.
- Las funciones que implementan callbacks de un behaviour no necesitan un `@spec` propio: el contrato está en el `@callback` correspondiente. Marca esas implementaciones con `@impl true` cuando proceda.
- No se exigen specs para funciones privadas (`defp`) ni para funciones generadas por macros o bibliotecas.
