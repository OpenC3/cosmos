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
  <div
    :class="[
      'state-panel d-flex flex-column flex-grow-1 min-h-0',
      { 'cursor-pointer': !!openDetails },
    ]"
    @click="showDetails()"
  >
    <div class="d-flex align-center ga-2">
      <status-symbol :level="first.level" :size="16" />
      <span
        :class="['state-value text-truncate', { 'text-disabled': first.stale }]"
        data-test="state-value"
      >
        {{ first.text }}
      </span>
    </div>
    <packet-time
      v-if="packetTime"
      :time="packetTime"
      class="state-time mt-auto"
      data-test="state-packet-time"
    />
  </div>
</template>

<script setup>
import { panelProps } from './panelBase'
import { useTlmPanel } from './tlmPanel'
import PacketTime from '../components/PacketTime.vue'
import StatusSymbol from '../components/StatusSymbol.vue'

const props = defineProps(panelProps)
const { first, packetTime, showDetails } = useTlmPanel(props)
</script>

<style scoped>
.state-panel {
  container-type: size;
  /* Padding in CSS rather than utilities so the queries below can change it */
  padding: 4px 16px 8px;
}
.state-value {
  /* Scales with the panel so narrow tiles show the whole state */
  font-size: clamp(14px, 9cqw, 24px);
  font-weight: 500;
  letter-spacing: 0.01em;
  line-height: 1.15;
}
/* At the bottom, and short enough that a 2 row panel (58px under the
   header) fits the state and the time with padding below */
.state-time {
  line-height: 16px;
}
/* One column wide */
@container (max-width: 120px) {
  .state-panel {
    padding-inline: 8px;
  }
}
</style>
