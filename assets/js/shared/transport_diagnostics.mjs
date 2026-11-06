export function connectTransportDiagnostics(socket, target = window) {
  // Pass bounded transport facts to active playback hooks; never forward raw errors/reasons.
  const transportEvent = (diagnostic, extra = {}) => target.dispatchEvent(
    new CustomEvent("bolognesa:transport", {detail: {diagnostic, ...extra}}))
  socket.onOpen(() => transportEvent("socket_open"))
  socket.onError(() => transportEvent("socket_error"))
  socket.onClose(event => transportEvent("socket_closed", {
    ws_code: event?.code, ws_clean: event?.wasClean,
  }))
}
