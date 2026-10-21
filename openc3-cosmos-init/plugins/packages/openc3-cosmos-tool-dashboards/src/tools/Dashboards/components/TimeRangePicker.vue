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
  <v-menu v-model="open" :close-on-content-click="false" location="bottom end">
    <template #activator="{ props }">
      <v-btn
        v-bind="props"
        variant="outlined"
        :prepend-icon="compact ? undefined : 'mdi-clock-outline'"
        append-icon="mdi-chevron-down"
        :title="`Time range: ${label}`"
        data-test="time-range"
      >
        {{ compact ? shortLabel : label }}
      </v-btn>
    </template>
    <!-- The menu is teleported out of the page, so it needs dashboards-root
         for the shared styles; the current range is marked like the current
         dashboard in the navigator -->
    <v-card class="dashboards-root" min-width="280" data-test="time-range-menu">
      <v-list density="compact" class="db-current-list py-1">
        <v-list-subheader>Quick ranges</v-list-subheader>
        <v-list-item
          v-for="seconds in presets"
          :key="seconds"
          :title="labelFor(seconds)"
          :class="{ current: seconds === modelValue }"
          :aria-current="seconds === modelValue || undefined"
          :data-test="`time-range-${seconds}`"
          @click="choose(seconds)"
        >
          <template v-if="seconds === modelValue" #append>
            <v-icon icon="mdi-check" color="secondary" size="18" />
          </template>
        </v-list-item>
      </v-list>
      <v-divider />
      <form class="pa-3" @submit.prevent="applyCustom">
        <div class="text-caption text-medium-emphasis mb-2">Custom range</div>
        <div class="d-flex ga-2">
          <v-text-field
            v-model.number="amount"
            label="Last"
            type="number"
            min="1"
            density="compact"
            variant="outlined"
            hide-details
            data-test="time-range-amount"
          />
          <v-select
            v-model="unit"
            :items="units"
            density="compact"
            variant="outlined"
            hide-details
            style="max-width: 130px"
            data-test="time-range-unit"
          />
        </div>
        <div v-if="problem" class="text-caption text-error mt-1">
          {{ problem }}
        </div>
        <v-btn
          type="submit"
          color="primary"
          variant="flat"
          block
          class="mt-3"
          :disabled="!!problem"
          data-test="time-range-apply"
        >
          Apply
        </v-btn>
      </form>
    </v-card>
  </v-menu>
</template>

<script>
import {
  TIME_RANGE_PRESETS,
  TIME_RANGE_UNITS,
  splitTimeRange,
  timeRangeLabel,
  timeRangeProblem,
} from '../composables/timeRange'

// Header button that picks the dashboard's time range in seconds: a quick
// range, or a custom number of seconds, minutes or hours
export default {
  props: {
    modelValue: { type: Number, required: true },
    // Phones show "5m" instead of "Last 5 minutes"
    compact: { type: Boolean, default: false },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      open: false,
      amount: null,
      unit: 60,
      presets: TIME_RANGE_PRESETS,
      units: TIME_RANGE_UNITS,
    }
  },
  computed: {
    label() {
      return timeRangeLabel(this.modelValue)
    },
    shortLabel() {
      return timeRangeLabel(this.modelValue, true)
    },
    customSeconds() {
      return Math.round(Number(this.amount) * this.unit)
    },
    problem() {
      return timeRangeProblem(this.customSeconds)
    },
  },
  watch: {
    // The custom fields start from the current range
    open(open) {
      if (open) [this.amount, this.unit] = splitTimeRange(this.modelValue)
    },
  },
  methods: {
    labelFor(seconds) {
      return timeRangeLabel(seconds)
    },
    choose(seconds) {
      this.$emit('update:modelValue', seconds)
      this.open = false
    },
    applyCustom() {
      if (!this.problem) this.choose(this.customSeconds)
    },
  },
}
</script>
