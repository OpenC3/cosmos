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

import { ref } from 'vue'

/**
 * @param {Object} state A ref object representing the current state of the script runner, expected to have values like 'waiting', 'paused', etc.
 */
export function useHandleWaiting(state) {
  const waitingTime = ref(0)
  const waitingInterval = ref(null)
  const waitingStart = ref(0)

  // Methods for waiting state
  const clearWaiting = () => {
    waitingTime.value = 0
    clearInterval(waitingInterval.value)
    waitingInterval.value = null
  }

  const handleWaiting = () => {
    // First check if we're not waiting and if so clear the interval
    if (state.value !== 'waiting' && state.value !== 'paused') {
      clearWaiting()
    } else if (waitingInterval.value !== null) {
      // If we're waiting and the interval is active then nothing to do
      return
    }
    waitingStart.value = Date.now()
    // Create an interval to count every second
    waitingInterval.value = setInterval(() => {
      waitingTime.value = Math.round((Date.now() - waitingStart.value) / 1000)
    }, 1000)
  }

  return { handleWaiting, waitingTime }
}
