/** Pure display-state transitions. Media effects and operation lifetimes live outside the model. */
export const createPlaybackState = () => ({selected: null, loading: false, finished: false, error: null})

export const selectionStarted = state => ({...state, loading: true, error: null})

export const selectionAccepted = (state, track) => ({
  ...state, selected: {...track}, loading: false, finished: false, error: null,
})

export const selectionFailed = (state, code) => ({
  ...state, loading: false, error: {code, retryable: true},
})
