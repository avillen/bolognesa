# Producto

Bolognesa es un mediacenter personal construido con Elixir y Phoenix. Su objetivo es practicar Elixir con problemas reales y llegar a utilizarlo habitualmente como biblioteca multimedia doméstica.

## Entorno y usuarios

- Despliegue previsto: un servidor Linux con Docker Compose. El QNAP TS-233 es el primer servidor y entorno validado; la capacidad bajo uso real y varias comprobaciones de reproducción siguen pendientes.
- Clientes iniciales: navegador de ordenador durante el desarrollo, móvil y navegador de una televisión Hisense de aproximadamente seis años. El propietario comprobó que la página base se ve bien en móvil y televisión; la compatibilidad de reproducción sigue pendiente.
- Una cuenta administradora al principio, con identidad real y datos personales asociados a su usuario. Se prevén cuentas independientes posteriormente.
- El acceso privado mediante Tailscale está habilitado en QNAP y pendiente de probar desde otro dispositivo de la tailnet. El acceso remoto general sigue siendo trabajo futuro.

## Primera versión utilizable

Entrar, configurar una carpeta de películas, escanearla, identificar sus obras, corregir coincidencias, reproducir un archivo compatible y continuar desde la posición guardada.

El contenido original se trata como solo lectura: no se mueve, renombra ni elimina. La primera reproducción es directa; no se presupone que cualquier formato funcione ni que el servidor doméstico pueda convertirlo en tiempo real.

## Ampliación priorizada: series

El propietario priorizó series antes de cerrar las validaciones domésticas pendientes. Bibliotecas de películas y series separadas, episodios `S01E02` y `1x02`, especiales y archivos con varios episodios están incluidos. Estos últimos se reproducen completos desde el principio con un aviso; no se prometen cortes ni reproducción automática. El [roadmap](roadmap.md) fija los criterios y el [estado](status.md) distingue implementación local de despliegue y pruebas reales.

## Visión posterior

Series, documentales, música, cuentas independientes, conversión de formatos cuando sea necesaria, acceso remoto y clientes específicos. Los documentales se representan como películas o series según su estructura.

Estas capacidades orientan los límites del diseño, pero no autorizan implementarlas todas de antemano. El siguiente trabajo se decide con el roadmap y el estado actual.

## Criterios de éxito

- Completar el recorrido inicial con archivos reales y registrar qué dispositivos y formatos funcionan.
- Mantener correcciones manuales y progreso después de reiniciar el servidor.
- Recuperar trabajos interrumpidos y explicar los fallos al usuario.
- Poder ampliar el proyecto entre sesiones a partir del repositorio, sin depender de conversaciones anteriores.

La arquitectura vigente está en [backend](conventions/backend.md) y [frontend](conventions/frontend.md); el orden de trabajo está en el [roadmap](roadmap.md).
