# Convenciones de Elixir

## Contratos públicos

- Declara un `@spec` para cada función pública (`def`) y macro público (`defmacro`). Sitúalo antes de la primera cláusula y cubre con un único contrato todas las cláusulas y argumentos por defecto.
- Usa tipos que expresen las entradas admitidas y los resultados posibles, incluidos los errores. Define `@type` cuando un tipo propio haga el contrato más claro.
- Las funciones que implementan callbacks de un behaviour no necesitan un `@spec` propio: el contrato está en el `@callback` correspondiente. Marca esas implementaciones con `@impl true` cuando proceda.
- No se exigen specs para funciones privadas (`defp`) ni para funciones generadas por macros o bibliotecas.
