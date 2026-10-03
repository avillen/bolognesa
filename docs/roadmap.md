# Roadmap

H0 (base de trabajo), P0 (prueba temprana de reproducción) y H1 (cuenta administradora) están implementados; H1 se publicó en QNAP el 2026-10-03 y el propietario completó el alta. Falta confirmar el recorrido autenticado con el propietario. La muestra MP4 de P0 funcionó en Hisense, móvil y ordenador; P0 no acredita los formatos de la biblioteca ni implementa el reproductor de H4. El [estado](status.md) recoge la situación real.

| Hito | Resultado | Criterios de aceptación |
| --- | --- | --- |
| H0. Base de trabajo | Convenciones mínimas de testing y observabilidad; evaluación del entorno real | Documentos acordados e indexados; procedimiento local reproducible; despliegue y montaje de solo lectura en QNAP verificados; interfaz base comprobada en móvil e Hisense. |
| P0. Prueba de reproducción (completa) | Viabilidad temprana del navegador y la entrega directa | Muestra pública servida por Bolognesa con rangos HTTP; imagen, sonido, pausa y salto observados en Hisense, móvil y ordenador; comportamiento del mando registrado; límites del resultado anotados. No acredita compatibilidad de toda la biblioteca. |
| H1. Cuenta administradora (alta completada en QNAP) | Primer acceso autenticado conforme a las capas acordadas | Arranque controlado sin registro público; iniciar y cerrar sesión; rechazo de acceso protegido sin sesión; identidad real del actor; pantalla inicial siguiendo frontend; pruebas relevantes y `mix precommit` correctos. Falta confirmar el recorrido autenticado con el propietario. |
| H2. Bibliotecas | Configuración de fuentes, inventario y análisis técnico | Escanear sin duplicados; fuentes inaccesibles sin bajas masivas; archivos ausentes marcados; trabajos recuperables; concurrencia limitada; originales intactos |
| H3. Catálogo e identificación | Películas reconocidas y corrección manual | Coincidencias y dudas visibles; corrección conservada ante reintentos y concurrencia; varias versiones de una obra; fallos del proveedor tratados |
| H4. Reproducción y actividad | Primer recorrido doméstico completo | Entrega directa autorizada con rangos; posición recuperada por usuario; emparejamiento de la TV desde un móvil autenticado; error explícito ante incompatibilidad; pruebas reales en dispositivos previstas y resultados documentados |

## Después de la primera versión

Priorizar según el uso real: recuperación de acceso a la cuenta, series, música, cuentas adicionales, conversión de formatos, acceso remoto y aplicaciones específicas. H1 no incluye recuperación de contraseña; su mecanismo se decidirá cuando se aborde. No se fija todavía un calendario ni una secuencia detallada entre esas ampliaciones.

## Cómo trabajar los hitos

1. Revisar requisitos y decisiones pendientes del hito.
2. Crear un plan pequeño con archivos afectados, criterios de aceptación y verificaciones.
3. Implementar y comprobar resultados; registrar limitaciones reales.
4. Actualizar estado y marcar el hito terminado únicamente si satisface sus criterios.

Las pruebas exploratorias de hardware no deben convertirse en una implementación improvisada del reproductor completo. P0 comprueba una muestra pública y los controles del navegador en los tres dispositivos; una película MP4 de la biblioteca se vio completa en ordenador. El propietario considera suficiente esa evidencia para avanzar con la estrategia de entrega directa en los tres clientes previstos. La compatibilidad de otros formatos y el recorrido autorizado se comprobarán al preparar H4. Esto no impide diseñar H1.
