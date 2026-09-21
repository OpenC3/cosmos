/* Copyright 2026 OpenC3, Inc. All Rights Reserved. See LICENSE.md. */

import { computed, onMounted, onBeforeUnmount, ref } from 'vue'
import { buildFlowMetrics, flowHealth } from './flowMetrics'

export function useFlowMetrics(api) {
  const metrics = ref(null)
  const unavailable = ref(false)
  const now = ref(Date.now())
  let active = false
  let timer
  let pending = false
  let lastRequest = -Infinity
  const flows = computed(() =>
    buildFlowMetrics(metrics.value, unavailable.value, now.value),
  )

  async function update() {
    now.value = Date.now()
    if (pending || now.value - lastRequest < 5000) return
    pending = true
    lastRequest = now.value
    try {
      const result = await api.get_metrics(true)
      if (active) {
        metrics.value = result
        unavailable.value = false
      }
    } catch (error) {
      if (active) {
        unavailable.value = true
        console.error(error)
      }
    } finally {
      pending = false
    }
  }

  onMounted(() => {
    active = true
    update()
    // Refresh ages between metric reports without adding API requests.
    timer = setInterval(update, 1000)
  })
  onBeforeUnmount(() => {
    active = false
    clearInterval(timer)
  })

  return (kind, name) =>
    flows.value[kind][name] || flowHealth([], unavailable.value)
}
