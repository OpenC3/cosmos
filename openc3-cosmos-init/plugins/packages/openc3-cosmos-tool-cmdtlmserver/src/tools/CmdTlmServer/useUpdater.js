/*
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

import { onBeforeUnmount, onMounted, toValue, watch } from 'vue'

/**
 * Calls an update function immediately on mount and then repeatedly on an
 * interval until the component unmounts.
 *
 * @param {Function} update Function to call on each interval
 * @param {number|Ref<number>|Function} refreshInterval In milliseconds, how
 *   often to call update. May be a number, ref, or getter (e.g. a prop
 *   accessor); changing it restarts the timer. Default is 1000 (1 second).
 */
export function useUpdater(update, refreshInterval = 1000) {
  let updater = null

  function clear() {
    if (updater != null) {
      clearInterval(updater)
      updater = null
    }
  }

  function changeUpdater() {
    clear()
    updater = setInterval(update, toValue(refreshInterval))
    update()
  }

  watch(() => toValue(refreshInterval), changeUpdater)

  onMounted(changeUpdater)
  onBeforeUnmount(clear)
}
