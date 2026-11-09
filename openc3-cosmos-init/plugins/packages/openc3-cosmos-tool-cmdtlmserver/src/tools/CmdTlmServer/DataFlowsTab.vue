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

const interfaceDetails = ref(null)
const routerDetails = ref(null)

function update() {
  api
    .get_interface_names()
    .then(async (names) => {
      const promises = [...names].map((name) => {
        return api.interface_details(name)
      })

      const responses = await Promise.all(promises)
      interfaceDetails.value = {}
      let index = 0
      names.forEach((name) => {
        interfaceDetails.value[name] = responses[index]
        index += 1
      })
    })
    .catch(console.error)

  api
    .get_router_names()
    .then(async (names) => {
      const promises = [...names].map((name) => {
        return api.router_details(name)
      })

      const responses = await Promise.all(promises)
      routerDetails.value = {}
      let index = 0
      names.forEach((name) => {
        routerDetails.value[name] = responses[index]
        index += 1
      })
    })
    .catch(console.error)
}

// call the update function every refreshInterval milliseconds
useUpdater(update, () => props.refreshInterval)
</script>
