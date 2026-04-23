/**
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { onUnmounted, ref, toValue } from 'vue'
import { Api, Cable } from '@openc3/js-common/services'

export const PAUSE = 'Pause'

export function useScriptOperations(
  emit,
  { updateOverridesCount, resetButtons, reloadFile },
  editor,
  readOnlyUser,
  inline,
  pauseOrRetryButton,
) {
  const receivedEvents = ref([])
  const scriptId = ref(null)
  const subscription = ref(null)

  const cable = new Cable('/script-api/cable')

  function received(data) {
    cable.recordPing()
    receivedEvents.value.push(data)
  }
  async function scriptStart(id) {
    emit('script-id', id)
    scriptId.value = id
    const newSubscription = await cable.createSubscription(
      'RunningScriptChannel',
      window.openc3Scope,
      {
        received,
      },
      {
        id: scriptId.value,
      },
    )
    subscription.value = newSubscription
  }
  async function scriptComplete() {
    // Make sure we process no more events
    if (subscription.value) {
      await subscription.value.unsubscribe()
      subscription.value = null
    }
    receivedEvents.value.length = 0 // Clear any unprocessed events

    await reloadFile() // Make sure the right file is shown
    // We may have changed the contents (if there were sub-scripts)
    // so don't let the undo manager think this is a change
    editor.value.session.getUndoManager().reset()
    if (!readOnlyUser.value && !toValue(inline)) {
      editor.value.setReadOnly(false)
    }

    scriptId.value = null // No current scriptId
    sessionStorage.removeItem('script_runner__script_id')

    // Lastly enable the buttons so another script can start
    resetButtons()
    // Overrides can be set from a script
    await updateOverridesCount()
  }
  function scriptDisconnect() {
    if (subscription.value) {
      subscription.value.unsubscribe()
      subscription.value = null
    }
    receivedEvents.value.length = 0 // Clear any unprocessed events
  }
  function stop() {
    Api.post(`/script-api/running-script/${scriptId.value}/stop`)
  }
  function step() {
    Api.post(`/script-api/running-script/${scriptId.value}/step`)
  }
  function pauseOrRetry() {
    if (pauseOrRetryButton.value === PAUSE) {
      Api.post(`/script-api/running-script/${scriptId.value}/pause`)
    } else {
      pauseOrRetryButton.value = PAUSE
      Api.post(`/script-api/running-script/${scriptId.value}/retry`)
    }
  }

  onUnmounted(() => {
    if (subscription.value) {
      subscription.value.unsubscribe()
      subscription.value = null
    }
    cable.disconnect()
  })

  return {
    pauseOrRetry,
    receivedEvents,
    scriptComplete,
    scriptDisconnect,
    scriptId,
    scriptStart,
    step,
    stop,
    subscription,
  }
}
