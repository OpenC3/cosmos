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
      'state-panel d-flex flex-column flex-grow-1 px-4 pt-2',
      { clickable: !!openDetails },
    ]"
    @click="openDetails && state.item && openDetails(state.item)"
  >
    <div class="d-flex align-center ga-2">
      <status-symbol :level="state.level" :size="16" />
      <span
        :class="['state-value text-truncate', { 'text-disabled': state.stale }]"
        data-test="state-value"
      >
        {{ state.text }}
      </span>
    </div>
    <div
      v-if="packetTime"
      class="d-flex align-center justify-end ga-1 pt-1 text-caption text-medium-emphasis num"
      :title="`Packet time ${packetTime}`"
      data-test="state-packet-time"
    >
      <v-icon icon="mdi-clock-outline" size="12" />
      <span class="text-truncate">{{ packetTime }}</span>
    </div>
  </div>
</template>

<script>
import tlmPanel from './tlmPanel'
import StatusSymbol from '../components/StatusSymbol.vue'

export default {
  components: { StatusSymbol },
  mixins: [tlmPanel],
  computed: {
    state() {
      return this.itemStates[0] || { text: '--' }
    },
  },
}
</script>

<style scoped>
.clickable {
  cursor: pointer;
}
.state-panel {
  container-type: inline-size;
}
.state-value {
  /* Scales with the panel so narrow tiles show the whole state */
  font-size: clamp(14px, 9cqw, 24px);
  font-weight: 500;
  letter-spacing: 0.01em;
  line-height: 1.25;
}
</style>
