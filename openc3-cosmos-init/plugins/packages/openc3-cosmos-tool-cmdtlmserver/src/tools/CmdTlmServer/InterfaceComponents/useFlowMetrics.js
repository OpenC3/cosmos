/* Copyright 2026 OpenC3, Inc. All Rights Reserved. See LICENSE.md. */

import { onMounted, onBeforeUnmount, shallowRef } from 'vue'
import { buildFlowMetrics, flowHealth } from './flowMetrics'

// Services publish metrics about every five seconds
const REFRESH_MS = 5000

export function useFlowMetrics(api) {
  // Rebuilt only when a request finishes, so nodes re-render at most once per
  // refresh. Ages and staleness are as of that request.
  const flows = shallowRef(buildFlowMetrics(null))
  // Shared by every node without metrics so its prop only changes per refresh
  const noMetrics = shallowRef(flowHealth())
  let metrics = null
  let active = false
  let timer
  let pending = false

  async function update() {
    if (pending) return
    pending = true
    let failed = false
    try {
      metrics = await api.get_metrics(true)
    } catch (error) {
      failed = true
      console.error(error)
    } finally {
      pending = false
    }
    if (!active) return
    flows.value = buildFlowMetrics(metrics, failed)
    noMetrics.value = flowHealth([], failed, flows.value.lag)
  }

  onMounted(() => {
    active = true
    void update()
    timer = setInterval(update, REFRESH_MS)
  })
  onBeforeUnmount(() => {
    active = false
    clearInterval(timer)
  })

  return (kind, name) => flows.value[kind][name] || noMetrics.value
}
