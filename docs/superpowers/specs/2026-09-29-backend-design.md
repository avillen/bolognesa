# Bolognesa: arquitectura del backend

Estado: propuesta consolidada para revisión. Recoge las decisiones acordadas; no es todavía un plan de implementación.

## Objetivo y entorno

Bolognesa es un mediacenter personal para practicar Elixir y llegar a utilizarlo de forma habitual. La visión incluye películas, series, documentales y música, con identificación, reproducción, cuentas independientes y futuros clientes.

El primer despliegue será en un QNAP TS-233 dentro de la red local. El acceso remoto llegará posteriormente. El primer cliente será web, utilizado desde ordenador, móvil y navegador de una televisión Hisense de aproximadamente seis años. La compatibilidad multimedia del televisor no está verificada.

El repositorio parte de una aplicación Phoenix con Ecto y PostgreSQL. Se mantendrá una única aplicación y un único despliegue inicial, organizados por contextos delimitados. No se requieren umbrella ni servicios independientes.

## Alcance inicial

El primer recorrido completo será: entrar con una cuenta administradora, configurar una carpeta de películas, escanearla, identificar las obras, corregir coincidencias, reproducir un archivo compatible y recuperar el progreso.

El acceso a los archivos originales será de lectura. Bolognesa no los moverá, renombrará ni eliminará.

Quedan para fases posteriores las series, la música, la transcodificación, las aplicaciones específicas, la gestión de varias cuentas y el acceso remoto. Los documentales se modelarán como películas o series según su estructura.

## Arquitectura y dependencias

Se aplicará DDD con dominio independiente de Ecto y arquitectura hexagonal dentro de cada contexto.

- **Dominio:** structs, objetos de valor, agregados, invariantes y transiciones. No depende de Phoenix, Ecto, Req, ejecución de procesos externos ni del sistema de archivos.
- **Aplicación:** casos de uso que coordinan autorización, dominio y puertos. Define qué cambios necesitan una transacción.
- **Puertos:** behaviours con operaciones concretas que la aplicación necesita del exterior.
- **Infraestructura:** adaptadores Ecto, consultas, mappers, sistema de archivos, proveedores HTTP y herramientas multimedia.
- **Fachada:** operaciones públicas del contexto. Los consumidores no acceden a sus schemas ni repositorios internos.

Ejemplo orientativo de organización, creando únicamente los módulos necesarios para cada caso de uso:

```text
lib/bolognesa/libraries/
  domain/
    library.ex
    media_file.ex
    source_path.ex
  application/
    create_library.ex
    scan_library.ex
    ports/
      library_repository.ex
      file_source.ex
  infrastructure/
    persistence/
      library_schema.ex
      library_mapper.ex
      ecto_library_repository.ex
    local_file_source.ex
  libraries.ex
```

El cableado de adaptadores se realiza fuera del dominio. Se inyectan dependencias en los casos de uso con un mecanismo uniforme que se concretará en el primer plan de implementación. Las pruebas no deben modificar configuración global mientras se ejecutan concurrentemente.

## Convenciones del dominio y persistencia

- Las entidades tienen identidad interna propia; los identificadores de proveedores externos son referencias adicionales.
- Las funciones de construcción y modificación comprueban invariantes y devuelven `{:ok, resultado}` o `{:error, motivo}`. Los errores esperables tienen motivos explícitos y estables.
- Los schemas Ecto representan almacenamiento. Los mappers convierten entre estos schemas y entidades del dominio.
- Los changesets comprueban requisitos de persistencia; las reglas de negocio viven en el dominio. Las restricciones de base de datos también protegen unicidad e integridad ante concurrencia.
- Los repositorios exponen necesidades concretas del dominio, sin devolver queries o changesets a la aplicación. No se introduce un repositorio CRUD genérico.
- Un puerto de transacciones permite ejecutar una unidad atómica sin exponer `Ecto.Multi` al caso de uso. No se mantiene una transacción abierta durante consultas HTTP, escaneos o análisis multimedia.
- Los agregados son pequeños y delimitan consistencia transaccional. Una biblioteca no contiene todos sus archivos en memoria; una serie tampoco implica cargar todos sus episodios.
- Cada contexto controla las escrituras de sus datos. Las referencias entre contextos utilizan identificadores y sus interfaces públicas.
- Las lecturas pueden utilizar proyecciones específicas, sin reconstruir agregados completos. Las consultas que cruzan contextos se encapsulan en adaptadores de lectura explícitos; no conceden permiso para modificar datos ajenos.
- Una entidad no corresponde a un proceso OTP. Los procesos se reservan para coordinación, concurrencia, supervisión y estado temporal.
- No se introduce event sourcing ni CQRS completo.

## Contextos delimitados

### Identidad y acceso

Controla usuarios, credenciales y autorización sobre bibliotecas. Inicialmente existe una cuenta administradora, creada mediante un procedimiento de arranque controlado y sin registro público. No hay un usuario fijo en código.

Las bibliotecas pertenecen a la instalación. El administrador inicial puede acceder a todas. La política de autorización permite incorporar permisos explícitos por biblioteca cuando se habiliten cuentas adicionales.

Los casos de uso protegidos reciben la identidad del actor, obtenida de una autenticación verificada; no confían en un identificador arbitrario enviado por el cliente. La autorización se comprueba en el backend, incluida la entrega del contenido.

### Bibliotecas

Controla las fuentes y el inventario físico:

- `Library`: nombre, tipo de contenido y fuentes configuradas.
- `MediaFile`: ubicación, disponibilidad y características técnicas conocidas.
- `Scan`: ejecución, progreso, resultado y errores.

Son agregados separados. Los escaneos repetidos reconcilian archivos sin duplicarlos. Un archivo ausente se marca como no disponible y conserva su referencia e identificación.

Solo un recorrido completo y correcto de una fuente permite concluir que un archivo está ausente. Una fuente inaccesible o un escaneo parcial registra un error y no convierte todos sus archivos en desaparecidos.

El primer alcance no garantiza reconocer automáticamente un archivo movido o renombrado como el mismo archivo. La estrategia concreta de identidad física y detección de cambios se decidirá en el diseño del escáner; no debe prometerse deduplicación por contenido sin implementarla.

### Catálogo

Describe obras con independencia de su disponibilidad física. El primer agregado es `Movie`. Una película puede no tener archivos disponibles o estar relacionada con varias versiones físicas.

Los conceptos futuros son `Series`, `Season`, `Episode`, `Artist`, `Album` y `Track`. Sus límites transaccionales se diseñarán en sus fases; no se implementan por adelantado.

Catálogo controla los metadatos internos de la obra y sus referencias a proveedores. Identificación utiliza su fachada para localizar o incorporar una obra.

### Identificación

Relaciona archivos con obras. `Identification` conserva el estado, los candidatos, la decisión y su procedencia automática o manual.

Una coincidencia dudosa requiere revisión. Una corrección manual queda protegida ante posteriores identificaciones automáticas. Esta protección debe comprobarse al guardar, incluso si un trabajo automático comenzó antes de la corrección.

La relación confirmada referencia el identificador del archivo y de la obra. Identificación controla esa relación; no se mantienen dos fuentes de verdad independientes en Bibliotecas y Catálogo.

Los adaptadores de proveedores normalizan respuestas externas antes de entregarlas a la aplicación. Las peticiones HTTP se realizan con Req.

### Reproducción

Controla autorización, selección del archivo y pistas, estrategia de entrega y sesiones. `StartPlayback` recibe el actor, la obra y las capacidades conocidas del cliente, comprueba acceso y disponibilidad y devuelve un plan de reproducción o un motivo de rechazo explícito.

Inicialmente solo se ofrece reproducción directa. Las capacidades declaradas por el cliente orientan la selección, pero no garantizan que su navegador pueda reproducir el contenido. La compatibilidad real se valida con archivos de prueba en los dispositivos previstos.

La entrega debe soportar peticiones de rangos de bytes para buscar posiciones. Cada petición de contenido requiere autorización, también cuando el navegador la realiza fuera del canal interactivo de la página. Los clientes solicitan identificadores autorizados, no rutas de disco arbitrarias.

La conversión de formatos tendrá un puerto propio cuando se implemente. No se asume capacidad de transcodificación del NAS sin una evaluación previa.

### Actividad personal

Controla posición, estado de visualización y, posteriormente, favoritos. Los datos pertenecen desde el primer día a un usuario y una obra, no a una cuenta implícita ni exclusivamente al archivo seleccionado.

El progreso se guarda periódicamente y al pausar; cerrar correctamente el navegador no es un requisito para conservarlo. La política para escrituras fuera de orden o sesiones simultáneas se concretará al diseñar este contexto.

## Casos de uso y flujo

1. `CreateLibrary`: configura una biblioteca y su fuente.
2. `StartScan`: registra la solicitud de escaneo.
3. `DiscoverFiles`: descubre y reconcilia archivos.
4. `InspectMediaFile`: obtiene contenedor, codecs, duración y pistas mediante un adaptador de herramientas multimedia.
5. `IdentifyMediaFile`: busca candidatos y confirma una coincidencia o deja pendiente la revisión.
6. `CorrectIdentification`: establece una coincidencia manual protegida.
7. `StartPlayback`: autoriza y prepara la reproducción directa.
8. Guardar y consultar progreso por usuario y obra.

Los nombres son vocabulario inicial, no una obligación de crear un módulo por cada operación trivial.

## Trabajos, eventos y recuperación

Los trabajos largos se ejecutan fuera de las peticiones web, con persistencia, reintentos y concurrencia limitada configurable. Los ejecutores llaman a casos de uso; el dominio no depende del motor de trabajos.

Se utilizan llamadas síncronas entre fachadas cuando hace falta un resultado inmediato. Las consecuencias independientes se disparan mediante eventos persistidos, por ejemplo, el descubrimiento de un archivo puede desencadenar su inspección.

El evento se guarda en la misma transacción que el cambio que lo produce, mediante un outbox. Un despachador recuperable entrega el trabajo posterior. PubSub puede notificar cambios a clientes conectados, pero no sustituye la persistencia.

La entrega es al menos una vez: los consumidores y casos de uso deben tolerar duplicados. La generación del archivo o escaneo asociada a un trabajo permite rechazar resultados obsoletos. No se promete ejecución exactamente una vez.

Los fallos transitorios se reintentan de forma acotada. Los errores permanentes o los reintentos agotados quedan visibles y permiten una nueva ejecución explícita. Los registros incluyen identificadores de trabajo, escaneo y archivo para facilitar el diagnóstico.

La selección del motor de trabajos, proveedores de metadatos y herramientas multimedia requiere una decisión técnica durante los planes respectivos. Este documento fija los contratos y garantías, no dependencias aún no evaluadas.

## Pruebas y criterios de aceptación

- Dominio: pruebas sin base de datos de invariantes, transiciones y errores.
- Aplicación: pruebas con adaptadores de prueba de autorización, coordinación, reintentos e idempotencia.
- Infraestructura: pruebas con PostgreSQL de mapeo, restricciones, transacciones y outbox; pruebas controladas de disco y proveedores.
- Procesos: inicio supervisado y sincronización determinista conforme a AGENTS.md.
- Integración: el primer recorrido completo funciona con una carpeta de películas y una cuenta administradora.

Casos esenciales: escaneo repetido sin duplicados; fuente inaccesible sin bajas masivas; recuperación tras reinicio; evento duplicado sin efectos duplicados; corrección manual protegida ante un trabajo concurrente; acceso a contenido rechazado sin autenticación válida; progreso recuperado en una sesión posterior.

La reproducción se prueba temprano en ordenador, móvil y televisión con archivos representativos. El resultado determina el alcance práctico de la reproducción directa y las necesidades posteriores de conversión.

Después de cambios de implementación se ejecutará `mix precommit` y se resolverán sus incidencias.

## Fases de implementación

1. **Fundación y cuenta inicial:** convenciones ejecutables, persistencia, autenticación y autorización mínima.
2. **Bibliotecas:** fuentes de lectura, escaneo, inventario y análisis técnico, con trabajos recuperables.
3. **Catálogo e identificación:** películas, proveedor de metadatos y corrección manual.
4. **Reproducción y actividad:** entrega directa autorizada y progreso por usuario; validación temprana de compatibilidad antes de invertir en el reproductor completo.
5. **Ampliaciones:** series, música, cuentas adicionales, conversión, acceso remoto y clientes específicos, priorizados según el uso real.

Cada fase tendrá un diseño acotado y un plan verificable. El diseño de LiveView se abordará después de revisar esta arquitectura del backend. No se define aún una API HTTP pública para futuros clientes, pero los casos de uso no dependerán de LiveView.
