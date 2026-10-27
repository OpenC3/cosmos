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
  <v-dialog
    v-model="show"
    :max-width="sheet ? undefined : 560"
    :content-class="sheet ? 'details-sheet' : undefined"
    :transition="sheet ? 'dialog-bottom-transition' : undefined"
    scrollable
  >
    <v-card
      v-if="item"
      :class="['dashboards-root', sheet ? 'rounded-t-xl' : 'rounded-lg']"
      :aria-label="`${item.itemName} details`"
      data-test="item-details"
    >
      <div class="d-flex align-start ga-2 pl-5 pr-2 pt-4">
        <div class="flex-grow-1 min-w-0">
          <div class="mono text-h6 text-truncate">{{ item.itemName }}</div>
          <div class="text-caption text-medium-emphasis text-truncate">
            {{ item.targetName }} {{ item.packetName }}
            <template v-if="info.description"
              >· {{ info.description }}</template
            >
          </div>
        </div>
        <v-btn
          icon="mdi-close"
          variant="text"
          size="small"
          aria-label="Close"
          @click="show = false"
        />
      </div>
      <v-card-text class="d-flex flex-column ga-4">
        <div class="d-flex align-center ga-3">
          <div class="d-flex align-baseline ga-2 min-w-0">
            <span
              :class="[
                'big-value num text-truncate',
                { 'text-disabled': stale },
              ]"
              data-test="item-details-value"
            >
              {{ display }}
            </span>
            <span class="text-body-1 text-medium-emphasis">{{
              info.units
            }}</span>
          </div>
          <v-spacer />
          <status-symbol
            v-if="level"
            :level="level"
            :size="24"
            class="flex-shrink-0"
          />
        </div>

        <!-- The limits are listed rather than marked under the bar, where
             numbers can't line up with their zones -->
        <div v-if="limits" class="d-flex flex-column ga-3">
          <limits-bar :limits="limits" :value="number" class="big-bar" />
          <div class="meta" data-test="item-details-limits">
            <div v-for="limit in limitRows" :key="limit.label">
              <div
                class="d-flex align-center ga-1 text-caption text-medium-emphasis"
              >
                <status-symbol :level="limit.level" :size="10" decorative />
                {{ limit.label }}
              </div>
              <div class="num text-truncate">
                {{ limit.value }} {{ info.units }}
              </div>
            </div>
          </div>
        </div>

        <div>
          <div class="text-caption text-medium-emphasis mb-1">
            {{ graphLabel }}
          </div>
          <div class="d-flex flex-column" style="height: 180px">
            <graph-panel v-if="graphable" :panel="graphPanel" />
            <div v-else class="text-caption text-medium-emphasis">
              Not a numeric item
            </div>
          </div>
        </div>

        <div class="meta">
          <div>
            <div class="text-caption text-medium-emphasis">Raw</div>
            <div class="num text-truncate">{{ raw }}</div>
          </div>
          <div>
            <div class="text-caption text-medium-emphasis">Packet time</div>
            <div class="num text-truncate">{{ packetTime }}</div>
          </div>
          <div>
            <div class="text-caption text-medium-emphasis">Limits set</div>
            <div>{{ limits ? itemInfo.state.limitsSet : 'No limits' }}</div>
          </div>
        </div>

        <v-btn
          v-if="showGrapher"
          variant="outlined"
          prepend-icon="mdi-chart-line"
          :href="grapherUrl"
          target="_blank"
          data-test="item-details-grapher"
        >
          Open in Telemetry Grapher
        </v-btn>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { computed, inject, onUnmounted, unref, watch } from 'vue'
import GraphPanel from '../panels/GraphPanel.vue'
import LimitsBar from './LimitsBar.vue'
import StatusSymbol from './StatusSymbol.vue'
import { itemKey, packetTimeKey } from '../composables/tlmPoller'
import {
  formatItem,
  formatTelemetry,
  formatTime,
  toSeconds,
} from '../composables/format'
import { timeRangeLabel } from '../composables/timeRange'
import { stateToLevel } from '../status'

// Everything about one item: big value, status, limits, a short graph, raw
// value and packet time. Slides up from the bottom on phones.
const props = defineProps({
  item: { type: Object, default: null },
  sheet: Boolean,
  // Telemetry Grapher is a desktop tool, so phones and tablets don't link to it
  showGrapher: { type: Boolean, default: true },
})
const show = defineModel({ type: Boolean })

const poller = inject('poller')
const itemInfo = inject('itemInfo')
const injectedTimeZone = inject('timeZone', 'local')
// { seconds } from the header's time range picker, which the graph follows
const timeRange = inject('timeRange', () => ({ seconds: 120 }), true)

const timeZone = computed(() => unref(injectedTimeZone))
const keys = computed(() => ({
  converted: itemKey(props.item, 'CONVERTED'),
  raw: itemKey(props.item, 'RAW'),
  packetTime: packetTimeKey(props.item),
}))
const info = computed(() => itemInfo.get(props.item))
const converted = computed(() => poller.values[keys.value.converted])
const number = computed(() =>
  typeof converted.value?.value === 'number' ? converted.value.value : null,
)
const display = computed(() =>
  formatItem(
    props.item.itemName,
    converted.value?.value,
    info.value.formatString,
    timeZone.value,
  ),
)
const raw = computed(() =>
  formatTelemetry(poller.values[keys.value.raw]?.value),
)
const packetTime = computed(() => {
  const time = poller.values[keys.value.packetTime]?.value ?? '--'
  return toSeconds(formatTime(time, timeZone.value))
})
const level = computed(() => stateToLevel(converted.value?.state))
const stale = computed(() => converted.value?.state === 'STALE')
const limits = computed(() => itemInfo.limits(props.item))
// Low beside high, outermost first, in the bar's colors (operational
// limits, when the item has them, are the bar's blue zone)
const limitRows = computed(() => {
  const l = limits.value
  const rows = [
    ['critical', 'Red low', l.red_low],
    ['critical', 'Red high', l.red_high],
    ['caution', 'Yellow low', l.yellow_low],
    ['caution', 'Yellow high', l.yellow_high],
  ]
  if (l.green_low !== undefined && l.green_high !== undefined) {
    rows.push(
      ['normal', 'Green low', l.green_low],
      ['normal', 'Green high', l.green_high],
    )
  }
  return rows.map(([level, label, value]) => ({ level, label, value }))
})
const graphLabel = computed(() => timeRangeLabel(timeRange.seconds))
const graphable = computed(() => number.value !== null || !converted.value)
const graphPanel = computed(() => ({
  uid: 0,
  type: 'GRAPH',
  items: [{ ...props.item, valueType: 'CONVERTED' }],
  settings: {},
}))
const grapherUrl = computed(() => {
  const { targetName, packetName, itemName } = props.item
  return `/tools/tlmgrapher/${[targetName, packetName, itemName]
    .map(encodeURIComponent)
    .join('/')}`
})

// Keeps the poller's registrations (external) in step with the item prop
watch(
  keys,
  (newKeys, oldKeys) => {
    if (oldKeys) poller.unregister(Object.values(oldKeys))
    poller.register(Object.values(newKeys))
  },
  { immediate: true },
)

onUnmounted(() => {
  poller.unregister(Object.values(keys.value))
})
</script>

<style>
/* On phones the details slide up from the bottom edge like a sheet */
.details-sheet {
  align-self: flex-end !important;
  margin: 0 !important;
  width: 100% !important;
  max-height: 85vh !important;
}
</style>

<style scoped>
.big-value {
  font-size: 44px;
  font-weight: 500;
  letter-spacing: -0.02em;
  line-height: 1;
}
.big-bar {
  transform: scaleY(1.5);
  transform-origin: top;
}
.meta {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px 16px;
}
</style>
