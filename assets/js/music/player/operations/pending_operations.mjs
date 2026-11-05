import {createCommandTracker} from "../adapters/commands.mjs"

/** Cancellation, replacement barriers and FIFO commits; never owns playback/queue state. */
export function createPendingOperations() {
  const commands = createCommandTracker()
  let generation = 0
  let appendChain = Promise.resolve()
  let replacement = null

  function resetAppends() {
    generation++
    appendChain = Promise.resolve()
  }
  function beginReplacement() {
    let finish
    const done = new Promise(resolve => { finish = resolve })
    replacement = {done, finish}
    return replacement
  }
  function finishReplacement(token) {
    const current = replacement === token
    if (current) replacement = null
    token.finish()
    return current
  }
  function append(request, commit) {
    const currentGeneration = generation
    const barrier = replacement
    // Observe the request immediately, even when an earlier append is still pending.
    const pending = request.then(result => ({result}), error => ({error}))
    const operation = appendChain.then(async () => {
      if (barrier) await barrier.done
      const {result, error} = await pending
      if (currentGeneration !== generation) return false
      if (error) throw error
      return commit(result)
    })
    appendChain = operation.catch(() => {})
    return operation
  }
  function clear() {
    resetAppends()
    replacement = null
    commands.start()
  }
  return {...commands, resetAppends, beginReplacement, finishReplacement, append, clear,
    get replacing() { return replacement !== null },
  }
}
