# Roadmap

Todos los hitos funcionales están pendientes. Solo se detalla el siguiente trabajo; cada hito tendrá su plan acotado cuando se aborde. El [estado](status.md) recoge la situación real.

| Hito | Resultado | Criterios de aceptación |
| --- | --- | --- |
| H0. Base de trabajo | Convenciones mínimas de testing y observabilidad; evaluación del entorno real | Documentos acordados e indexados; procedimiento local reproducible; viabilidad de despliegue y montaje de carpetas de lectura en QNAP registrada, o bloqueo concreto; prueba exploratoria de reproducción en Hisense con resultados o acceso pendiente explícito |
| H1. Cuenta administradora | Primer acceso autenticado conforme a las capas acordadas | Arranque controlado sin registro público; iniciar y cerrar sesión; rechazo de acceso protegido sin sesión; identidad real del actor; pantalla inicial siguiendo frontend; pruebas relevantes y `mix precommit` correctos |
| H2. Bibliotecas | Configuración de fuentes, inventario y análisis técnico | Escanear sin duplicados; fuentes inaccesibles sin bajas masivas; archivos ausentes marcados; trabajos recuperables; concurrencia limitada; originales intactos |
| H3. Catálogo e identificación | Películas reconocidas y corrección manual | Coincidencias y dudas visibles; corrección conservada ante reintentos y concurrencia; varias versiones de una obra; fallos del proveedor tratados |
| H4. Reproducción y actividad | Primer recorrido doméstico completo | Entrega directa autorizada con rangos; posición recuperada por usuario; error explícito ante incompatibilidad; pruebas reales en dispositivos previstas y resultados documentados |

## Después de la primera versión

Priorizar según el uso real: series, música, cuentas adicionales, conversión de formatos, acceso remoto y aplicaciones específicas. No se fija todavía un calendario ni una secuencia detallada entre esas ampliaciones.

## Cómo trabajar los hitos

1. Revisar requisitos y decisiones pendientes del hito.
2. Crear un plan pequeño con archivos afectados, criterios de aceptación y verificaciones.
3. Implementar y comprobar resultados; registrar limitaciones reales.
4. Actualizar estado y marcar el hito terminado únicamente si satisface sus criterios.

Las pruebas exploratorias de hardware no deben convertirse en una implementación improvisada del reproductor completo. Si requieren acceso físico o credenciales del usuario, registrar esa dependencia y avanzar en tareas independientes. H0 no está terminado hasta resolver sus comprobaciones; un bloqueo físico no impide diseñar H1.
