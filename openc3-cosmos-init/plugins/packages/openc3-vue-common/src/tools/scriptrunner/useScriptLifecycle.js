/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { computed, ref } from 'vue'
import { Api, OpenC3Api } from '@openc3/js-common/services'

export const LIFECYCLE_STATE_LABELS = {
  development: 'In Development',
  review: 'In Review',
  approved: 'Approved',
}

export const LIFECYCLE_STATE_COLORS = {
  development: 'primary',
  review: 'orange',
  approved: 'green',
}

export function lifecycleStateLabel(state) {
  return LIFECYCLE_STATE_LABELS[state] || state
}

export function lifecycleStateColor(state) {
  return LIFECYCLE_STATE_COLORS[state] || 'primary'
}

// Per-instance script lifecycle state. The lifecycle follows the open file,
// so callers must fetchLifecycle() on file load and resetLifecycle() when
// clearing the editor.
export function useScriptLifecycle() {
  const lifecycleEnabled = ref(false)
  const lifecycleState = ref('development')
  const lifecycleHistory = ref([])
  const showLifecycle = ref(false)

  const scriptApproved = computed(() => {
    return lifecycleEnabled.value && lifecycleState.value === 'approved'
  })
  const lifecycleLabel = computed(() => {
    return lifecycleStateLabel(lifecycleState.value)
  })
  const lifecycleColor = computed(() => {
    return lifecycleStateColor(lifecycleState.value)
  })

  // Read the Script Lifecycle feature flag (Admin / Settings)
  async function loadLifecycleSetting() {
    try {
      const response = await new OpenC3Api().get_setting(
        'script_runner_lifecycle',
      )
      if (response !== null && response !== undefined) {
        lifecycleEnabled.value = response
      }
    } catch (error) {
      // Keep default (false)
    }
  }

  function resetLifecycle() {
    lifecycleState.value = 'development'
    lifecycleHistory.value = []
  }

  function fetchLifecycle(filename) {
    if (!lifecycleEnabled.value || !filename) {
      resetLifecycle()
      return
    }
    Api.get(`/script-api/scripts/${filename}/lifecycle`)
      .then((response) => {
        lifecycleState.value = response.data.state
        lifecycleHistory.value = response.data.history
      })
      .catch((error) => {
        // Treat unknown lifecycle as development (no restrictions)
        resetLifecycle()
      })
  }

  function lifecycleUpdated(lifecycle) {
    lifecycleState.value = lifecycle.state
    lifecycleHistory.value = lifecycle.history
  }

  return {
    lifecycleEnabled,
    lifecycleState,
    lifecycleHistory,
    showLifecycle,
    scriptApproved,
    lifecycleLabel,
    lifecycleColor,
    loadLifecycleSetting,
    resetLifecycle,
    fetchLifecycle,
    lifecycleUpdated,
  }
}
