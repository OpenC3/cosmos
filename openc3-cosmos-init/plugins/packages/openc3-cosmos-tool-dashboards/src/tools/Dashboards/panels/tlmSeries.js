/*
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
*/

import { computed, inject, onMounted, onUnmounted, reactive, watch } from 'vue'
import { itemKey } from '../composables/tlmPoller'
import { SeriesStore, alignSeries } from '../composables/seriesStore'
import { pollType } from './tlmPanel'

// The value nearest `time` in a series that has gaps (rows from other
// packets are null), searching up to `reach` seconds either side like the
// graph's cursor. Past the newest point it's the newest value, however old,
// so slow items still show one. Returns null when there's nothing near.
export function nearestValue(times, values, time, reach) {
  if (!times?.length || time === null || time < times[0]) return null
  let low = 0
  let high = times.length - 1
  if (time >= times[high]) {
    for (let i = high; i >= 0; i--) {
      if (typeof values[i] === 'number') return values[i]
    }
    return null
  }
  while (high - low > 1) {
    const mid = (low + high) >> 1
    if (times[mid] < time) low = mid
    else high = mid
  }
  let best = null
  let bestGap = Infinity
  for (let i = low; i >= 0 && time - times[i] <= reach; i--) {
    if (typeof values[i] === 'number') {
      best = values[i]
      bestGap = time - times[i]
      break
    }
  }
  for (let i = high; i < times.length; i++) {
    const gap = times[i] - time
    if (gap > reach || gap >= bestGap) break
    if (typeof values[i] === 'number') return values[i]
  }
  return best
}

// How far either side of the cursor a value still counts as under it
export function hoverReach(seconds) {
  return Math.max(5, seconds / 40)
}

// Panels that draw their items over time. The dashboard's SeriesStore
// (composables/seriesStore.js) backfills the time range picked in the header
// and then streams live (the way Telemetry Grapher does), or during playback
// loads the range before the playback time, sharing one stream and one
// clock across every panel. `base` is what usePanel or useTlmPanel returned.
//
// Options are getters / callbacks read once the panel mounts:
// `seriesItems` (default: the panel's items), `seriesUpdated()` called about
// once a second with points older than the range dropped, and
// `seriesReset()` called when the panel's items change (default:
// seriesUpdated). Returns `series` ([times in seconds, then one array of
// values per item], oldest first) and `latest` (each item's newest value);
// both are plain arrays updated in place, not reactive, and with one item
// they're the store's own arrays, so treat them as read only.
export function useTlmSeries(props, base, options = {}) {
  const { poller, cable, timeline } = base
  // { seconds } from the header's time range picker
  const timeRange = inject('timeRange', () => ({ seconds: 120 }), true)
  // { time, source }: hover shared across the dashboard's graphs
  const hover = inject(
    'hover',
    () => reactive({ time: null, source: null }),
    true,
  )
  // The dashboard's (DashboardGrid); a panel shown outside a grid gets one
  // of its own
  const shared = inject('seriesStore', null)
  const store =
    shared ?? new SeriesStore({ poller, cable, timeRange, timeline })

  const now = computed(() => store.state.now)
  // Seconds of history shown
  const duration = computed(() => timeRange.seconds)
  const seriesItems = computed(
    () => options.seriesItems?.() ?? props.panel.items,
  )
  const streamKeys = computed(() =>
    seriesItems.value.map(
      (item) => `DECOM__TLM__${itemKey(item, pollType(item))}`,
    ),
  )

  const series = [[]]
  const latest = []
  let keys = []
  let stopTicks = null

  const seriesUpdated = () => options.seriesUpdated?.()
  const seriesReset = () =>
    options.seriesReset ? options.seriesReset() : seriesUpdated()

  // Share the time under the mouse (seconds, or null on leave)
  function setHover(time) {
    if (time === null) {
      // Only the panel that set it clears it
      if (hover.source !== props.panel.uid) return
      hover.source = null
    } else {
      hover.source = props.panel.uid
    }
    hover.time = time
  }

  // Point series and latest at the store's arrays for the current keys
  function refresh() {
    const entries = keys.map((key) => store.get(key))
    series.splice(0, series.length, ...alignSeries(entries))
    latest.splice(
      0,
      latest.length,
      ...entries.map((entry) => entry?.latest ?? null),
    )
  }

  function setKeys(next) {
    store.release(keys)
    keys = next
    store.acquire(keys)
    refresh()
    seriesReset()
  }

  onMounted(() => {
    setKeys(streamKeys.value)
    stopTicks = store.onTick(() => {
      refresh()
      seriesUpdated()
    })
    // The store is outside Vue: keep the keys it streams in step with the
    // panel's items, which change with a new panel config (no event)
    watch(streamKeys, (next, previous) => {
      if (next.join() !== previous.join()) setKeys(next)
    })
  })
  onUnmounted(() => {
    stopTicks?.()
    store.release(keys)
    if (!shared) store.dispose()
  })

  return {
    timeRange,
    hover,
    now,
    duration,
    seriesItems,
    series,
    latest,
    setHover,
    // Start the history over, e.g. after a gap
    restart: () => store.restart(),
  }
}
