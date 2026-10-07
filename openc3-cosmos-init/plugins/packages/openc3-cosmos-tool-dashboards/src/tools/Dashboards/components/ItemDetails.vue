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
        <div class="flex-grow-1" style="min-width: 0">
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
          <div class="d-flex align-baseline ga-2" style="min-width: 0">
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

        <div v-if="limits">
          <limits-bar :limits="limits" :value="number" class="big-bar" />
          <div
            class="d-flex justify-space-between text-caption text-medium-emphasis num mt-1"
          >
            <span>{{ limits.red_low }}</span>
            <span>{{ limits.yellow_low }}</span>
            <span>{{ limits.yellow_high }}</span>
            <span>{{ limits.red_high }}</span>
          </div>
        </div>

        <div>
          <div class="text-caption text-medium-emphasis mb-1">Last 2 min</div>
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
          <div>
            <div class="text-caption text-medium-emphasis">Range</div>
            <div class="num">{{ range }}</div>
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

<script>
import GraphPanel from '../panels/GraphPanel.vue'
import LimitsBar from './LimitsBar.vue'
import StatusSymbol from './StatusSymbol.vue'
import modelShow from '../mixins/modelShow'
import { itemKey, packetTimeKey } from '../composables/tlmPoller'
import { formatTelemetry, toSeconds } from '../composables/format'
import { stateToLevel } from '../status'

// Everything about one item: big value, status, limits, a short graph, raw
// value and packet time. Slides up from the bottom on phones.
export default {
  components: { GraphPanel, LimitsBar, StatusSymbol },
  mixins: [modelShow],
  inject: ['poller', 'itemInfo'],
  props: {
    item: { type: Object, default: null },
    sheet: Boolean,
    // Telemetry Grapher is a desktop tool, so phones and tablets don't link to it
    showGrapher: { type: Boolean, default: true },
  },
  computed: {
    keys() {
      return {
        converted: itemKey(this.item, 'CONVERTED'),
        raw: itemKey(this.item, 'RAW'),
        packetTime: packetTimeKey(this.item),
      }
    },
    info() {
      return this.itemInfo.get(this.item)
    },
    converted() {
      return this.poller.values[this.keys.converted]
    },
    number() {
      return typeof this.converted?.value === 'number'
        ? this.converted.value
        : null
    },
    display() {
      return formatTelemetry(this.converted?.value, this.info.formatString)
    },
    raw() {
      return formatTelemetry(this.poller.values[this.keys.raw]?.value)
    },
    packetTime() {
      return toSeconds(this.poller.values[this.keys.packetTime]?.value ?? '--')
    },
    level() {
      return stateToLevel(this.converted?.state)
    },
    stale() {
      return this.converted?.state === 'STALE'
    },
    limits() {
      return this.itemInfo.limits(this.item)
    },
    range() {
      const l = this.limits
      if (!l) return '--'
      return `${l.yellow_low} to ${l.yellow_high} ${this.info.units}`.trim()
    },
    graphable() {
      return this.number !== null || !this.converted
    },
    graphPanel() {
      return {
        uid: 0,
        type: 'GRAPH',
        items: [{ ...this.item, valueType: 'CONVERTED' }],
        settings: { DURATION: ['2'] },
      }
    },
    grapherUrl() {
      const { targetName, packetName, itemName } = this.item
      return `/tools/tlmgrapher/${targetName}/${packetName}/${itemName}`
    },
  },
  watch: {
    keys: {
      immediate: true,
      handler(keys, oldKeys) {
        if (oldKeys) this.poller.unregister(Object.values(oldKeys))
        this.poller.register(Object.values(keys))
      },
    },
  },
  unmounted() {
    this.poller.unregister(Object.values(this.keys))
  },
}
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
