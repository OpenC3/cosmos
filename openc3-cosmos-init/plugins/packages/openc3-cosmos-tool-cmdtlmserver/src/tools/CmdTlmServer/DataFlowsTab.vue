<!--
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
-->

<template>
  <InterfaceFlowChart
    :interface-details="interfaceDetails"
    :router-details="routerDetails"
    style="height: 80vh"
  />
</template>

<script setup>
import { OpenC3Api } from '@openc3/js-common/services'
import { ref } from 'vue'
import InterfaceFlowChart from './InterfaceComponents/InterfaceFlowChart.vue'
import { useUpdater } from './useUpdater'

const props = defineProps({
  refreshInterval: {
    type: Number,
    default: 1000,
  },
})

const api = new OpenC3Api()

/**
 * Keeps a { name: details } ref up to date, e.g. for all interfaces.
 *
 * Each item is refreshed independently. An interface or router whose
 * microservice isn't running makes its details call wait for a 30s timeout
 * and fail, which must neither delay the others nor stack up requests:
 *  - results are applied as soon as they arrive
 *  - a failed item keeps its last good details
 *  - an item with a request outstanding is skipped until it finishes
 */
function useDetails(getNames, getDetails) {
  const details = ref(null)
  // Plain (non-reactive) bookkeeping
  let currentNames = new Set()
  let namesPending = false
  const pending = new Set() // names with a details request outstanding
  const failed = new Set() // names whose failure was already logged

  async function refreshOne(name) {
    if (pending.has(name)) return
    pending.add(name)
    try {
      const result = await getDetails(name)
      failed.delete(name)
      // Ignore the result if the item was removed in the meantime
      if (currentNames.has(name)) {
        details.value = { ...details.value, [name]: result }
      }
    } catch (error) {
      if (!failed.has(name)) {
        failed.add(name)
        console.error(`Unable to get details for ${name}`, error)
      }
    } finally {
      pending.delete(name)
    }
  }

  async function update() {
    if (namesPending) return
    namesPending = true
    try {
      currentNames = new Set(await getNames())
      // Drop items that no longer exist. Publishing right away means the
      // chart renders without waiting for any details request.
      details.value = Object.fromEntries(
        Object.entries(details.value || {}).filter(([name]) =>
          currentNames.has(name),
        ),
      )
      currentNames.forEach(refreshOne)
    } catch (error) {
      console.error(error)
    } finally {
      namesPending = false
    }
  }

  return { details, update }
}

const { details: interfaceDetails, update: updateInterfaces } = useDetails(
  () => api.get_interface_names(),
  (name) => api.interface_details(name),
)
const { details: routerDetails, update: updateRouters } = useDetails(
  () => api.get_router_names(),
  (name) => api.router_details(name),
)

function update() {
  // Intentionally not awaited: interfaces and routers refresh independently so
  // a slow one doesn't delay the other. Each update guards against overlapping
  // runs and catches its own errors, so neither can reject or stack up.
  void updateInterfaces()
  void updateRouters()
}

// call the update function every refreshInterval milliseconds
useUpdater(update, () => props.refreshInterval)
</script>
