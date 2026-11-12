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
    class="aggregate d-flex flex-column flex-grow-1 min-h-0"
    data-test="aggregate-panel"
  >
    <!-- One item: its limits bar (the current value, and min to max
         bracketed), then a tile per statistic -->
    <limits-bar
      v-if="rows.length === 1 && rows[0].range"
      class="aggregate-range mx-3 mt-1 mb-2 flex-shrink-0"
      :limits="rows[0].range.limits"
      :value="rows[0].range.now"
      :range="rows[0].range.span"
      :title="
        rows[0].range.span
          ? 'The current value, and a bracket from the min to the max over the time range'
          : 'The current value'
      "
      data-test="aggregate-range-bar"
    />
    <div
      v-if="rows.length === 1"
      ref="tiles"
      :class="[
        'aggregate-tiles flex-grow-1 min-h-0 overflow-auto px-3 pt-1',
        { 'cursor-pointer': !!openDetails },
      ]"
      :style="{ '--tile-columns': tileColumns }"
      :tabindex="openDetails ? 0 : undefined"
      @click="showDetails()"
      @keydown.enter="showDetails()"
    >
      <div
        v-for="cell in rows[0].cells"
        :key="cell.name"
        :class="[
          'aggregate-tile d-flex flex-column justify-center rounded pa-2',
          cell.out,
        ]"
        :data-test="`aggregate-${cell.name}`"
      >
        <div
          class="d-flex align-center ga-1 text-caption text-medium-emphasis min-w-0"
        >
          <status-symbol
            v-if="cell.out"
            :level="cell.level"
            class="flex-shrink-0"
          />
          <span class="text-truncate">{{ cell.title }}</span>
        </div>
        <div class="d-flex align-baseline ga-1 min-w-0">
          <span
            :class="[
              'tile-value num text-truncate',
              { 'text-disabled': rows[0].stale },
            ]"
            data-test="aggregate-value"
          >
            {{ cell.text }}
          </span>
          <span class="text-caption text-medium-emphasis text-no-wrap">
            {{ cell.units }}
          </span>
        </div>
      </div>
    </div>

    <!-- Several items: rows like the Values panel, a column per
         statistic and the units once at the end -->
    <div
      v-else-if="rows.length"
      class="aggregate-rows flex-grow-1 min-h-0 overflow-auto mt-2"
      :style="{ '--stat-columns': columns.length }"
    >
      <div class="aggregate-grid aggregate-head text-medium-emphasis">
        <span />
        <span />
        <span
          v-for="column in columns"
          :key="column.name"
          class="text-right text-truncate"
        >
          {{ column.title }}
        </span>
        <span />
      </div>
      <component
        :is="openDetails ? 'button' : 'div'"
        v-for="row in rows"
        :key="row.key"
        :type="openDetails ? 'button' : undefined"
        :class="[
          'db-row aggregate-grid aggregate-row w-100 text-left',
          row.level ? `t-${row.level}` : '',
          { 'value-button cursor-pointer': openDetails },
        ]"
        :title="openDetails ? `${row.path}: details` : row.path"
        data-test="aggregate-row"
        @click="showDetails(row.item)"
      >
        <span class="d-flex">
          <status-symbol :level="row.level" />
        </span>
        <span class="aggregate-label mono text-medium-emphasis text-truncate">
          {{ row.label }}
        </span>
        <span
          v-for="cell in row.cells"
          :key="cell.name"
          :class="[
            'num font-weight-medium text-right text-no-wrap',
            { 'text-disabled': row.stale },
          ]"
          data-test="aggregate-value"
        >
          <!-- Out of limits: a status pill with its symbol -->
          <span v-if="cell.out" :class="['out-pill', cell.out]">
            <status-symbol :level="cell.level" />
            {{ cell.text }}
          </span>
          <template v-else>{{ cell.text }}</template>
        </span>
        <span class="text-caption text-disabled text-truncate">
          {{ row.units }}
        </span>
      </component>
    </div>
    <div v-else class="pa-4 text-caption text-medium-emphasis">
      No items. Configure this panel to add some.
    </div>

    <div
      v-if="rows.length"
      class="aggregate-footer flex-0-0 px-4 pb-2 pt-1 text-caption text-medium-emphasis text-truncate"
      data-test="aggregate-range"
    >
      {{ rangeText }}
    </div>
  </div>
</template>

<script setup>
import {
  computed,
  onMounted,
  onUnmounted,
  ref,
  useTemplateRef,
  watch,
} from 'vue'
import { panelProps } from './panelBase'
import { useTlmPanel } from './tlmPanel'
import { useTlmSeries } from './tlmSeries'
import { option } from './options'
import { STATISTICS, aggregate, limitsLevel } from './aggregate'
import { compactNumber, formatTelemetry } from '../composables/format'
import { dependOn } from '../composables/dependOn'
import { timeRangeLabel } from '../composables/timeRange'
import StatusSymbol from '../components/StatusSymbol.vue'
import LimitsBar from '../components/LimitsBar.vue'

// Min, max, average and other statistics of each item over the dashboard's
// time range (the history graphs show), updated about once a second. During
// playback it's the range before the playback time.
//
// Kept cheap for long ranges of fast items: each item's history is read as
// is (not merged onto one time axis like a graph's), only the chosen
// statistics are computed, and an item's are only recomputed when its
// history changed. While the history reloads (a new time range, a jump in
// playback, a reconnect) the last values stay, dimmed, instead of
// flashing to --.
const HOLD_MS = 5000

const props = defineProps(panelProps)
const panel = useTlmPanel(props)
const {
  itemStates,
  itemInfo,
  poller,
  showDetails,
  openDetails,
  isNarrow,
  isPlayback,
} = panel
const version = ref(0)
const { duration, entries } = useTlmSeries(props, panel, {
  aligned: false,
  seriesUpdated: () => version.value++,
})
// Stream key => { signature, stats, dataAt } for the last computed stats
const cache = new Map()

const chosen = computed(() => option(props.panel, 'STATS'))
const showBar = computed(() => option(props.panel, 'LIMITS_BAR'))
const columns = computed(() =>
  STATISTICS.filter((stat) => chosen.value.includes(stat.value)).map(
    (stat) => ({
      ...stat,
      name: stat.value,
      title:
        stat.value === 'PERCENTILE'
          ? `P${option(props.panel, 'PERCENTILE')}`
          : stat.title,
    }),
  ),
)
// An item's statistics, from the cache unless its history or the options
// changed. Returns { stats, stale }.
function statsFor(key, entry, settings) {
  const times = entry?.times ?? []
  const values = entry?.values ?? []
  // Points are added at the end and trimmed from the start, so the length
  // and the ends say whether anything changed
  const signature = `${settings}|${times.length}|${times[0]}|${times.at(-1)}|${values.at(-1)}`
  const cached = cache.get(key)
  if (cached?.signature === signature) return { stats: cached.stats }
  const stats = aggregate(values, {
    percentile: option(props.panel, 'PERCENTILE'),
    stats: chosen.value,
  })
  const now = Date.now()
  if (
    !stats.COUNT &&
    cached?.stats.COUNT &&
    (poller.clock.loading > 0 || now - cached.dataAt < HOLD_MS)
  ) {
    // Emptied for a reload: keep the last values until it's back
    return { stats: cached.stats, stale: true }
  }
  cache.set(key, {
    signature,
    stats,
    dataAt: stats.COUNT ? now : (cached?.dataAt ?? 0),
  })
  return { stats }
}

const rows = computed(() => {
  // The store's arrays change in place; the version says when
  dependOn(version.value)
  const settings = `${chosen.value.join()}|${option(props.panel, 'PERCENTILE')}`
  const keys = new Set()
  const result = itemStates.value.map((state, index) => {
    const key = `${state.key}|${state.item.valueType}`
    keys.add(key)
    const { stats, stale } = statsFor(key, entries[index], settings)
    const info = itemInfo.get(state.item)
    const raw = state.item.valueType === 'RAW'
    const units = raw ? '' : info.units
    // Limits are in converted units, so raw values aren't checked
    const limits = raw ? null : state.limits
    return {
      item: state.item,
      key: state.key,
      label: state.label,
      path: state.path,
      // Current status, like the Values panel
      level: state.level,
      units,
      stale: !!stale,
      // The limits bar, for items with limits once there's data
      range:
        showBar.value && limits && stats.COUNT
          ? rangeBar(state, limits, stats)
          : null,
      cells: columns.value.map((column) => {
        const value = stats[column.name]
        // A reading out of its limits, e.g. a max that went red during the
        // range. Only caution and critical are called out, and not while
        // the values are held for a reload.
        const level = column.limits ? limitsLevel(value, limits) : null
        return {
          name: column.name,
          title: column.title,
          text: format(value, column.name, raw ? null : info.formatString),
          units: column.unitless ? '' : units,
          level,
          out:
            !stale && (level === 'caution' || level === 'critical')
              ? `out-${level}`
              : null,
        }
      }),
    }
  })
  // Forget items no longer shown
  for (const key of cache.keys()) if (!keys.has(key)) cache.delete(key)
  return result
})

// The limits bar for one item: the current value, like the Stat panel's,
// and a min to max bracket when those statistics are shown (min and max
// are computed whatever is shown)
function rangeBar(state, limits, stats) {
  const shown = (name) => chosen.value.includes(name)
  return {
    limits,
    now: state.number,
    span: shown('MIN') || shown('MAX') ? [stats.MIN, stats.MAX] : null,
  }
}

const rangeText = computed(
  () =>
    `${timeRangeLabel(duration.value)}${isPlayback.value ? ' before playback time' : ''}`,
)

// One item's tiles fill the panel: as many columns as fit at 140px or more,
// then evened out so every row is full where it can be (8 tiles in room for
// 5 is 4 x 2, not 5 + 3), with rows sharing the height
const TILE_MIN_WIDTH = 140
const TILE_GAP = 8
const tilesEl = useTemplateRef('tiles')
const tilesWidth = ref(0)
const tileColumns = computed(() => {
  const count = columns.value.length || 1
  const fit = Math.max(
    1,
    Math.floor((tilesWidth.value + TILE_GAP) / (TILE_MIN_WIDTH + TILE_GAP)),
  )
  const rowCount = Math.ceil(count / Math.min(fit, count))
  return Math.ceil(count / rowCount)
})
let tilesObserver = null
onMounted(() => {
  tilesObserver = new ResizeObserver(([entry]) => {
    tilesWidth.value = entry.contentRect.width
  })
  // The tiles come and go with the item count
  const observe = () => tilesEl.value && tilesObserver.observe(tilesEl.value)
  observe()
  watch(tilesEl, (el, old) => {
    if (old) tilesObserver.unobserve(old)
    observe()
  })
})
onUnmounted(() => tilesObserver?.disconnect())

function format(value, name, formatString) {
  if (value === null || value === undefined) return '--'
  if (name === 'COUNT')
    return isNarrow.value ? compactNumber(value) : value.toLocaleString()
  if (isNarrow.value) return compactNumber(value)
  if (formatString) {
    return formatTelemetry(value, formatString)
  }
  return Number(value.toPrecision(6)).toString()
}
</script>

<style scoped>
.aggregate {
  container-type: inline-size;
}
/* Columns from tileColumns; rows share the panel's height, at least
   tall enough for a title and value */
.aggregate-tiles {
  display: grid;
  grid-template-columns: repeat(var(--tile-columns, 1), minmax(0, 1fr));
  grid-auto-rows: minmax(56px, 1fr);
  gap: 8px;
}

.aggregate-tile {
  background: rgba(var(--v-theme-on-surface), 0.04);
  min-width: 0;
  /* Values grow with their tile, like the Stat panel's */
  container-type: size;
}
/* A statistic that went out of limits during the range: its status color
   strongly, plus the status symbol so it doesn't rely on color alone. The
   text keeps the theme's color so it reads on yellow too. */
.out-caution {
  --out: var(--color-status-caution);
  --out-tint: 22%;
}
.out-critical {
  --out: var(--color-status-critical);
  --out-tint: 30%;
}
.aggregate-tile.out-caution,
.aggregate-tile.out-critical {
  background: color-mix(in srgb, var(--out) var(--out-tint), transparent);
  box-shadow:
    inset 3px 0 0 var(--out),
    inset 0 0 0 1px color-mix(in srgb, var(--out) 55%, transparent);
}
.out-pill {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-right: -6px;
  padding: 1px 6px;
  border-radius: 4px;
  background: color-mix(in srgb, var(--out) var(--out-tint), transparent);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--out) 60%, transparent);
  font-weight: 600;
}
.tile-value {
  font-size: clamp(16px, min(14cqw, 36cqh), 40px);
  font-weight: 500;
  line-height: 1.2;
}
.aggregate-range {
  --limits-bar-track: 10px;
}
/* Rows like the Values panel: status, label, one column per statistic
   and the units */
.aggregate-grid {
  display: grid;
  grid-template-columns:
    12px minmax(48px, 1fr) repeat(var(--stat-columns), minmax(56px, 104px))
    28px;
  align-items: center;
  gap: 12px;
  padding-inline: 16px;
}
.aggregate-head {
  height: 24px;
  font-size: 11px;
}
.aggregate-row {
  height: 36px;
  color: inherit;
}
.aggregate-label {
  font-size: 12px;
}
.value-button:hover {
  background-color: rgba(var(--v-theme-on-surface), 0.04);
}
.value-button:focus-visible {
  outline: 2px solid rgb(var(--v-theme-primary));
  outline-offset: -2px;
}
@container (max-width: 340px) {
  .aggregate-grid {
    gap: 8px;
    padding-inline: 12px;
  }
  .aggregate-row {
    height: 30px;
    font-size: 12px;
  }
  .aggregate-label {
    font-size: 11px;
  }
}
</style>
