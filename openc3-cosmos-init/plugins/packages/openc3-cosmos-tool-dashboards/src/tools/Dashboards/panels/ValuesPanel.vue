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
  <div class="values-panel flex-grow-1 overflow-y-auto mt-2">
    <component
      :is="openDetails ? 'button' : 'div'"
      v-for="row in itemStates"
      :key="row.key"
      :type="openDetails ? 'button' : undefined"
      :class="[
        'db-row value-row d-flex align-center w-100 text-left',
        row.level ? `t-${row.level}` : '',
        { 'value-button': openDetails },
      ]"
      :title="openDetails ? `${row.path}: details` : row.path"
      data-test="values-row"
      @click="openDetails && openDetails(row.item)"
    >
      <span class="d-flex flex-shrink-0" style="width: 12px">
        <status-symbol :level="row.level" />
      </span>
      <span
        class="value-label mono text-medium-emphasis text-truncate flex-grow-1"
      >
        {{ row.label }}
      </span>
      <limits-bar
        v-if="showBars"
        class="values-bar flex-shrink-0"
        style="width: 56px"
        :limits="row.limits"
        :value="row.number"
      />
      <span
        :class="[
          'num font-weight-medium text-right text-no-wrap',
          { 'text-disabled': row.stale },
        ]"
        style="min-width: 64px"
        data-test="values-value"
      >
        {{ row.text }}
      </span>
      <span
        class="text-caption text-disabled flex-shrink-0"
        style="width: 28px"
      >
        {{ row.units }}
      </span>
    </component>
    <div
      v-if="!panel.items.length"
      class="pa-4 text-caption text-medium-emphasis"
    >
      No items. Configure this panel to add some.
    </div>
  </div>
</template>

<script>
import tlmPanel from './tlmPanel'
import { option } from './options'
import LimitsBar from '../components/LimitsBar.vue'
import StatusSymbol from '../components/StatusSymbol.vue'

export default {
  components: { LimitsBar, StatusSymbol },
  mixins: [tlmPanel],
  computed: {
    showBars() {
      return option(this.panel, 'LIMITS_BARS')
    },
  },
}
</script>

<style scoped>
.values-panel {
  container-type: inline-size;
}
.value-row {
  height: 36px;
  gap: 12px;
  padding-inline: 16px;
}
.value-label {
  font-size: 12px;
}
/* Narrow panels use smaller text and rows, then drop the limits bars (the
   row tint still shows status) */
@container (max-width: 340px) {
  .value-row {
    height: 30px;
    gap: 8px;
    padding-inline: 12px;
    font-size: 12px;
  }
  .value-label {
    font-size: 11px;
  }
}
@container (max-width: 280px) {
  .values-bar {
    display: none;
  }
}
.value-button {
  cursor: pointer;
  color: inherit;
}
.value-button:hover {
  background-color: rgba(var(--v-theme-on-surface), 0.04);
}
.value-button:focus-visible {
  outline: 2px solid rgb(var(--v-theme-primary));
  outline-offset: -2px;
}
</style>
