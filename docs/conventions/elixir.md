# Convenciones de Elixir

## Contratos públicos

- Declara un `@spec` para cada función pública (`def`) y macro público (`defmacro`). Sitúalo antes de la primera cláusula y cubre con un único contrato todas las cláusulas y argumentos por defecto.
- Usa tipos que expresen las entradas admitidas y los resultados posibles, incluidos los errores. Define `@type` cuando un tipo propio haga el contrato más claro.
- Evita tipos demasiado amplios como `term()` o `module()` en los contratos públicos. Usa tipos de dominio o de puerto con nombre (por ejemplo, `User.id()` o `Repository.adapter()`); para una struct, tipa sus campos con esos tipos propios.
- Da a los tipos temporales un nombre acorde con su significado: el instante recibido al crear una sesión es `issued_at()`, mientras que `expires_at()` describe el valor calculado y almacenado.
- Las funciones que implementan callbacks de un behaviour no necesitan un `@spec` propio: el contrato está en el `@callback` correspondiente. Marca esas implementaciones con `@impl true` cuando proceda.
- No se exigen specs para funciones privadas (`defp`) ni para funciones generadas por macros o bibliotecas.
