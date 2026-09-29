# 0001. Base arquitectónica

Estado: aceptada durante el diseño inicial con el propietario, 2026-09-29.

## Contexto

Proyecto personal de aprendizaje y uso doméstico, con múltiples dominios multimedia y un despliegue inicial en un NAS. Se busca mantener límites claros y continuidad entre sesiones, con una primera versión pequeña.

## Decisión

- Una aplicación Phoenix organizada por contextos delimitados.
- Dominio con structs y reglas independientes de Ecto; puertos y adaptadores para persistencia e integraciones.
- Entidades y schemas separados, con mappers explícitos.
- LiveViews pequeñas organizadas por funcionalidad y pantalla.
- Un archivo por reducer público, que recibe el socket y devuelve el socket mediante `call(socket, ...)`.
- `state/` para modelos de vista y `forms/` para changesets de presentación. No se duplica todo el socket en un estado paralelo.

## Alternativas consideradas

Se consideraron umbrella y servicios independientes; la aplicación única reduce trabajo operativo inicial. Se consideró compartir entidades con schemas Ecto; el propietario eligió practicar un dominio independiente. Se consideró un estado completo separado del socket; trabajar sobre el socket aprovecha directamente streams y efectos de LiveView.

## Consecuencias

Se acepta mantener mappers y más archivos por operación. Los reducers dependen de LiveView y pueden ejecutar efectos; no son reducers puros. Las abstracciones se introducen cuando un caso de uso las necesita.

Las reglas concretas se mantienen en [backend](../conventions/backend.md) y [frontend](../conventions/frontend.md), que deben consultarse al implementar.
