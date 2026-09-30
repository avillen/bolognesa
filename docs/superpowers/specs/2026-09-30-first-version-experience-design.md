# Experiencia de la primera versión de Bolognesa

Estado: diseño aprobado por el propietario el 2026-09-30. No es un plan de implementación.

## Propósito y plataformas

Bolognesa debe permitir elegir y ver una película desde el sofá con el mando, y también explorar y reproducir desde móvil y ordenador. La administración de bibliotecas se diseña inicialmente para móvil y ordenador. El navegador de la Hisense es un cliente previsto, pero su navegación y reproducción reales requieren pruebas en el dispositivo.

## Recorrido acordado

1. Tras iniciar sesión, Inicio muestra «Continuar viendo» como primera sección. Seleccionar una película ahí reanuda directamente.
2. Si no existe progreso, Inicio invita a explorar las películas.
3. Un menú lateral muestra Inicio, Películas y Buscar. Buscar forma parte de la primera versión; en la televisión se comprobará el teclado que ofrezca su navegador.
4. Seleccionar una obra desde Películas o Buscar abre una ficha cinematográfica con Reproducir como acción principal. La ficha admite información de disponibilidad y, cuando existan, varias versiones.
5. Un error de reproducción debe explicar el problema y permitir volver a la ficha. La falta de imagen utiliza un fondo alternativo sin perder legibilidad.

El recorrido se adapta a televisión, móvil y ordenador. La prioridad de diseño para explorar y reproducir es la televisión; esto no restringe la reproducción en otros dispositivos.

## Dirección visual e interacción

El inicio presenta varias películas para continuar y, debajo, una entrada al catálogo. La ficha usa una imagen de fondo protagonista con texto legible y la acción principal destacada. La paleta es cálida: fondos oscuros, texto claro y acento ámbar. Las imágenes de los bocetos fueron esquemáticas, no contenido real del catálogo.

Los enlaces y botones esenciales serán interactivos con ratón, tacto y teclado, sin depender de hover. En navegadores que entreguen foco de teclado, este debe destacar claramente, con respaldo para los que no admitan `:focus-visible`. La prueba P0 en la Hisense mostró que su navegador mueve un cursor con el mando y requiere hacer clic; por ello la interfaz de TV también necesita objetivos grandes y acciones frecuentes próximas. No se presupone navegación directa por foco ni recepción de las flechas por JavaScript. Si una prueba específica confirma que la página recibe esas teclas, podrá valorarse un hook; si el navegador las reserva para mover el cursor, el diseño debe funcionar bien con ese cursor. El retorno desde la reproducción y los estados de carga, vacío y error deben ser coherentes en las tres plataformas.

## Acceso a la televisión

La opción elegida es emparejar la televisión desde un móvil ya autenticado, evitando escribir credenciales largas con el mando. Se diseña ahora, pero se implementará antes del recorrido completo de reproducción en televisión, no necesariamente en H1. Su diseño de seguridad deberá concretar código de un solo uso, caducidad, confirmación, sesión independiente de la TV y revocación. H1 sigue centrado en la cuenta administradora y el acceso desde móvil y ordenador.

## Validación y secuencia

Antes de H1 se completó una prueba temporal de reproducción directa descrita en [la prueba de reproducción](../../plans/playback-probe.md). Imagen, sonido, pausa y salto funcionaron con la muestra pública MP4 en Hisense, móvil y ordenador; la TV también mostró el vídeo en pantalla completa. El navegador de la Hisense usa un cursor para hacer clic con el mando. Estos resultados orientan controles y navegación, pero no sustituyen H4: la entrega autorizada de medios privados, selección de archivo, progreso y mensajes de incompatibilidad se implementarán allí.

Membrane Framework queda como candidato a evaluar cuando exista una necesidad medida de procesar o convertir medios. La reproducción directa inicial solo requiere entregar rangos HTTP y dejar que el navegador decodifique el archivo.
