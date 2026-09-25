<!-- Copyright 2026 OpenC3, Inc. All Rights Reserved. See LICENSE.md. -->

<template>
  <section class="pa-4" data-test="flow-metrics">
    <div class="d-flex align-center flex-wrap ga-2 mb-3">
      <h3 class="text-subtitle-1">Processing metrics</h3>
      <v-chip :color="health.color" :prepend-icon="health.icon" size="small">
        {{ health.label }}
      </v-chip>
    </div>
    <v-alert
      v-if="health.state === 'unavailable'"
      type="warning"
      variant="tonal"
      density="compact"
      class="mb-3"
    >
      Unable to refresh metrics. Any values below are from the last successful
      request. Retrying automatically.
    </v-alert>
    <p class="text-body-2 mb-3">
      Latest reported measurements; services publish about every 5 seconds.
      Delay and duration warnings start at {{ delayWarning }} s (red at
      {{ delayCritical }} s). Buffered input warnings start at 1 MiB (red at 10
      MiB). Reports older than {{ staleSeconds }} seconds are stale. Idle
      services retain their last measurement. Totals reset on restart.
    </p>
    <v-data-table
      :headers="headers"
      :items="health.rows"
      :items-per-page="-1"
      item-value="id"
      density="compact"
      hide-default-footer
      no-data-text="No metrics reported yet for this node."
    >
      <template #item.service="{ item }">
        <span class="text-break">{{ item.service }}</span>
      </template>
      <template #item.label="{ item }">
        <span :title="`${item.metric}: ${item.help}`">{{ item.label }}</span>
      </template>
      <template #item.value="{ item }">
        <span class="metric-value">{{ item.value }}</span>
      </template>
      <template #item.status="{ item }">
        <v-chip
          :color="health.state === 'unavailable' ? 'warning' : item.color"
          size="small"
          variant="tonal"
        >
          {{ health.state === 'unavailable' ? 'Unavailable' : item.status }}
        </v-chip>
      </template>
      <template #item.age="{ item }">
        {{ item.age === null ? 'Unknown' : `${Math.floor(item.age)} s ago` }}
      </template>
    </v-data-table>
  </section>
</template>

<script setup>
import {
  DELAY_WARNING_SECONDS,
  DELAY_CRITICAL_SECONDS,
  STALE_SECONDS,
} from './flowMetrics'

defineProps({ health: { type: Object, required: true } })
const delayWarning = DELAY_WARNING_SECONDS
const delayCritical = DELAY_CRITICAL_SECONDS
const staleSeconds = STALE_SECONDS
const headers = [
  { title: 'Service', key: 'service' },
  { title: 'Metric', key: 'label' },
  { title: 'Value', key: 'value', sortable: false },
  { title: 'Status', key: 'status' },
  { title: 'Report age', key: 'age' },
]
</script>

<style scoped>
.metric-value {
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
</style>
