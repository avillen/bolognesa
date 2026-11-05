export function createCommandTracker() {
  let generation = 0;
  let controller = null;

  return {
    start() {
      generation++;
      controller?.abort();
      controller = null;
      return generation;
    },
    signal() {
      controller = new AbortController();
      return controller.signal;
    },
    isCurrent(command) {
      return command === generation;
    },
    finish(command) {
      if (command === generation) controller = null;
    },
  };
}
