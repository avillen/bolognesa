# Testing

Seguimos TDD centrado en comportamiento, con un esfuerzo proporcional al cambio. Las pruebas explican qué hace el sistema y protegen sus contratos observables; deben permitir refactorizar su implementación.

## Flujo de trabajo

1. Revisar las pruebas existentes del comportamiento que se va a modificar.
2. Para un cambio funcional, modificar una prueba relevante o añadir el escenario que falte y comprobar que falla por el motivo esperado.
3. Implementar el cambio necesario y comprobar la prueba.
4. Refactorizar implementación y pruebas, manteniendo el comportamiento verificado.
5. Ejecutar las comprobaciones adecuadas al cambio y `mix precommit` al finalizar.

Los cambios exclusivamente documentales o de formato no requieren nuevas pruebas ni un ciclo rojo/verde artificial. Una refactorización que conserva comportamiento se apoya en pruebas existentes; se cubren antes las carencias relevantes que se detecten.

## Evolución de las pruebas

- Modificar una prueba existente cuando cambie el comportamiento que describe. Añadir una cuando represente una situación distinta o una regresión todavía no cubierta.
- Conservar las regresiones que sigan siendo válidas. No eliminar cobertura útil para reducir el número de pruebas ni alterar expectativas solo para conseguir que pasen.
- Al añadir una prueba, revisar las cercanas para mejorar nombres, preparación y duplicación. Refactorizar localmente cuando aporte claridad, sin ampliar innecesariamente el alcance.
- Evitar helpers y fixtures excesivamente genéricos que oculten los datos relevantes de cada escenario.
- Nombrar las pruebas por el resultado o regla que verifican. Por ejemplo: «conserva la identificación manual al repetir el escaneo».

## Qué comprobar

Comprobar datos devueltos, reglas e invariantes, autorización, cambios persistidos y respuesta observable de la interfaz. Evitar funciones privadas, estructura interna del socket y orden exacto de llamadas salvo que ese orden sea en sí un contrato funcional necesario.

Elegir el nivel más directo que proteja el comportamiento y sus riesgos. No duplicar automáticamente cada escenario en todas las capas ni crear un archivo de pruebas por cada módulo de implementación.

| Área | Enfoque |
| --- | --- |
| Dominio | Pruebas sin base de datos de invariantes, transiciones y errores |
| Aplicación | Casos de uso mediante contratos públicos; dobles en puertos cuando ayuden a aislar efectos |
| Persistencia e infraestructura | Integración con PostgreSQL para restricciones, mappers, transacciones y outbox; recursos externos controlados |
| LiveView | Interacciones con LiveViewTest y selectores estables; resultados visibles y navegación |
| Reducers, modelos de vista y forms | Pruebas directas cuando una transición, transformación o validación relevante lo justifique |
| Trabajos y eventos | Recuperación, duplicados, resultados obsoletos y efectos duraderos; sincronización determinista |

Los dobles se sitúan en los límites externos. No se simula cada módulo interno. Las pruebas de integración verifican lo que un doble no puede garantizar, como atomicidad o restricciones de base de datos. Las pruebas normales no dependen de proveedores públicos ni del NAS o televisor reales.

Se siguen las reglas de procesos supervisados y sincronización de este documento, y los selectores de las convenciones de Phoenix. No se modifica configuración global desde pruebas concurrentes.

## Verificación proporcional

Durante el desarrollo ejecutar las pruebas afectadas; ampliar cuando exista un riesgo concreto o una comprobación obligatoria. Registrar los comandos ejecutados y sus resultados, distinguiendo los tests automatizados de las verificaciones manuales en dispositivos. No asumir compatibilidad de hardware a partir de pruebas unitarias.

## Procesos en pruebas

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
