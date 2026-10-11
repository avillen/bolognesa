# 0016. Idioma por cuenta y pantalla de Ajustes

Estado: implementada, verificada localmente y desplegada mediante `bf6447a`. Guardado autenticado en QNAP y validación visual pendientes. [Evidencia](../validation/qnap.md#despliegue-de-ajustes-e-idioma).

## Contexto

La interfaz tenía textos fijos en español y Gettext instalado para componentes comunes. El propietario solicita distintos idiomas según el locale y aprueba comenzar Ajustes con español e inglés, detección del navegador y una elección compartida entre dispositivos.

## Decisión

Identidad conserva la preferencia nullable `locale` del usuario. `nil` sigue el navegador; `es` y `en` son los valores explícitos. El dominio valida y la actualización solo utiliza el ID del actor verificado mediante fachada, caso de uso y repositorio existentes. La base de datos limita los valores admitidos.

La presentación resuelve preferencia de la cuenta → `Accept-Language` → español. Gettext se establece por proceso en HTTP y LiveView. Las variantes regionales se normalizan a los idiomas disponibles; se respetan calidad, orden y exclusiones. El documento raíz declara el idioma efectivo.

La ruta autenticada `/settings` contiene inicialmente el selector de idioma. Guardar fuerza recarga completa para actualizar también el documento HTML; la confirmación usa el idioma resultante. Otras pestañas y dispositivos recuperan la elección en la siguiente petición o montaje. No hay sincronización inmediata de pestañas.

Los textos propios se traducen en presentación con catálogos Gettext de español e inglés. Los motivos backend y los metadatos almacenados mantienen sus contratos. Los errores de formulario se extraen sin traducir y se traducen al mostrarlos. Las tareas asíncronas entregan datos y el proceso de la página prepara sus textos.

## Consecuencias

La preferencia se comparte entre dispositivos sin modificar las sesiones. Se acepta una migración aditiva y una recarga al guardar. El rollback pierde únicamente la preferencia nueva y conserva cuentas y credenciales. Guardarla solo en una cookie no cumple la elección por cuenta; un contexto genérico de configuración no se justifica para esta única preferencia.

Añadir otro idioma requiere definirlo en el objeto de valor, la restricción de persistencia, el resolver web y el selector, además de completar los catálogos. La cobertura automática comprueba traducciones y placeholders; no acredita apariencia ni funcionamiento de dispositivos reales.

## Referencias

- [Diseño](../designs/2026-10-11-settings-and-locale.md)
- [Plan](../plans/2026-10-11-settings-and-locale.md)
