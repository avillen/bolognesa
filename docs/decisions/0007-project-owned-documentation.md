# 0007. Documentación organizada por función

Estado: aceptada por el propietario el 2026-10-10.

## Contexto

Los diseños y planes de H1 y H3 vivían bajo `docs/superpowers/`, mientras que los de H2 y H4 estaban mezclados en `docs/plans/`. La ruta indicaba la herramienta usada para crearlos en vez de la función del documento. `AGENTS.md` reunía instrucciones de continuidad con reglas extensas de Phoenix y Elixir; `docs/status.md` mezclaba el estado vigente con verificaciones antiguas.

## Decisión

Organizar la documentación por propósito: convenciones vigentes en `docs/conventions/`, decisiones y motivos en `docs/decisions/`, diseños acordados en `docs/designs/`, planes de implementación en `docs/plans/`, comprobaciones observadas en `docs/validation/` y antecedentes en `docs/history/`. Mantener `docs/status.md` como instantánea breve del trabajo y sus pendientes.

Las habilidades, incluida Superpowers, pueden guiar el proceso, pero guardan sus artefactos en esas rutas. `AGENTS.md` indica cómo localizar las convenciones y conserva el protocolo de sesión; `CLAUDE.md` remite a las instrucciones compartidas.

## Consecuencias y alternativas

Mover archivos obliga a actualizar sus enlaces, pero deja una ubicación predecible para cada tipo de contenido. El historial de Git conserva los nombres antiguos. Mantener `docs/superpowers/` con un índice habría conservado dos criterios de clasificación; renombrar solo esa carpeta habría dejado diseños mezclados con planes. Se elige una única estructura del proyecto sin duplicar reglas por herramienta.
