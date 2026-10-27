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

import {
  computed,
  inject,
  onMounted,
  onUnmounted,
  reactive,
  ref,
  watch,
} from 'vue'
import { Cable } from '@openc3/js-common/services'
import { itemKey } from '../composables/tlmPoller'
import { pollType } from './tlmPanel'

const RENDER_MS = 1000

// Panels that draw their items over time. When the dashboard opens, the
// streaming API backfills the dashboard's time range (picked in the header)
// and then streams live (the way Telemetry Grapher does); during playback the
// range before the playback time is loaded instead. `base` is what usePanel
// or useTlmPanel returned.
//
// Options are getters / callbacks read once the panel mounts:
// `seriesItems` (default: the panel's items), `seriesUpdated()` called about
// once a second with points older than the range dropped, and
// `seriesReset()` called whenever the series start over (default:
// seriesUpdated). Returns `series` ([times in seconds, then one array of
// values per item], oldest first) and `latest` (each item's newest value);
// both are plain arrays updated in place, not reactive.
export function useTlmSeries(props, base, options = {}) {
  const { poller, cable, isPlayback, playbackTime } = base
  // { seconds } from the header's time range picker
  const timeRange = inject('timeRange', () => ({ seconds: 120 }), true)
  // { time, source }: hover shared across the dashboard's graphs
  const hover = inject(
    'hover',
    () => reactive({ time: null, source: null }),
    true,
  )

  const now = ref(Date.now() / 1000)
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

  const socket = cable || new Cable()
  let subscription = null
  // Bumped by every restart, so a subscription still connecting from an
  // earlier one is dropped instead of streaming alongside the new one
  let generation = 0
  const series = [[]]
  const latest = []
  let renderTimer = null
  let startTime = 0
  let needsAdd = false

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

  function restart() {
    const current = ++generation
    subscription?.unsubscribe()
    subscription = null
    series.splice(0, series.length, [], ...seriesItems.value.map(() => []))
    latest.splice(0, latest.length, ...seriesItems.value.map(() => null))
    seriesReset()
    // Nothing to draw, so no need to tick
    if (!seriesItems.value.length) {
      stopRender()
      return
    }
    renderTimer ??= setInterval(render, RENDER_MS)
    // Playback loads the window leading up to the playback time instead
    if (isPlayback.value) {
      if (playbackTime.value) {
        loadRange(
          new Date(playbackTime.value.getTime() - duration.value * 1000),
          playbackTime.value,
        )
      }
      return
    }
    startTime = (Date.now() - duration.value * 1000) * 1_000_000
    needsAdd = false
    socket
      .createSubscription('StreamingChannel', window.openc3Scope, {
        received: (rows) => {
          if (current !== generation) return
          socket.recordPing()
          append(rows)
        },
        // connected can fire before or after the promise below resolves, and
        // again after every reconnect, so both paths go through addItems
        connected: () => {
          if (current !== generation) return
          needsAdd = true
          addItems()
        },
      })
      .then((created) => {
        if (current !== generation) {
          created.unsubscribe()
          return
        }
        subscription = created
        addItems()
      })
  }

  function stopRender() {
    clearInterval(renderTimer)
    renderTimer = null
  }

  function addItems() {
    if (!subscription || !needsAdd) return
    needsAdd = false
    // Resume from the newest point we have so reconnects don't duplicate
    const last = series[0].at(-1)
    subscription.perform('add', {
      scope: window.openc3Scope,
      token: localStorage.openc3Token,
      items: streamKeys.value,
      start_time: last ? Math.floor(last * 1e9) + 1 : startTime,
    })
  }

  // Historical rows for playback, in the same shape the stream delivers
  async function loadRange(start, end) {
    const items = seriesItems.value
    if (!items.length) return
    const timeKey = itemKey(
      { ...items[0], itemName: 'PACKET_TIMESECONDS' },
      'RAW',
    )
    const keys = [
      timeKey,
      ...items.map((item) => itemKey(item, pollType(item))),
    ]
    poller.clock.loading++
    try {
      await poller.resolve(keys)
      const data = await poller.api.get_tlm_values(
        keys.map((key) => poller.available[key]),
        30,
        null,
        start,
        end,
        { 'Ignore-Errors': '403' },
      )
      // The playback time moved on while this loaded
      if (end !== playbackTime.value) return
      // One row comes back unwrapped
      const rows =
        Array.isArray(data?.[0]) && Array.isArray(data[0][0]) ? data : [data]
      append(
        rows
          .filter((row) => typeof row?.[0]?.[0] === 'number')
          .map((row) =>
            Object.fromEntries([
              ['__time', row[0][0] * 1e9],
              ...streamKeys.value.map((key, i) => [key, row[i + 1]?.[0]]),
            ]),
          ),
      )
      render()
    } catch (error) {
      console.error('Dashboards playback history failed:', error)
    } finally {
      poller.clock.loading--
    }
  }

  function append(rows) {
    const [xs, ...ys] = series
    const keys = streamKeys.value
    for (const row of rows) {
      if (!row.__time) continue
      const t = row.__time / 1e9
      let index = xs.length
      while (index > 0 && xs[index - 1] > t) index--
      if (index > 0 && xs[index - 1] === t) {
        index--
      } else {
        xs.splice(index, 0, t)
        ys.forEach((y) => y.splice(index, 0, null))
      }
      keys.forEach((key, i) => {
        if (key in row) {
          const value = typeof row[key] === 'number' ? row[key] : null
          ys[i][index] = value
          if (value !== null && index === xs.length - 1) latest[i] = value
        }
      })
    }
  }

  function render() {
    now.value = (playbackTime.value?.getTime() ?? Date.now()) / 1000
    // Drop points that scrolled off the left edge
    const cutoff = now.value - duration.value
    const xs = series[0]
    let drop = 0
    while (drop < xs.length && xs[drop] < cutoff) drop++
    if (drop > 0) series.forEach((values) => values.splice(0, drop))
    seriesUpdated()
  }

  onMounted(() => {
    restart()
    // The stream lives outside Vue: restart it when what's shown changes.
    // One watcher, so a change to several of these restarts once.
    watch(
      () => ({
        keys: streamKeys.value.join(),
        seconds: duration.value,
        playback: isPlayback.value,
        time: playbackTime.value,
      }),
      (next, previous) => {
        const sameView =
          next.keys === previous.keys &&
          next.seconds === previous.seconds &&
          next.playback === previous.playback
        if (sameView) {
          // Only the playback time moved (or nothing did)
          if (!next.playback || !next.time || +next.time === +previous.time) {
            return
          }
          // Stepping forward adds just the new range; anything else reloads
          const step = next.time - previous.time
          if (previous.time && step > 0 && step <= next.seconds * 1000) {
            loadRange(previous.time, next.time)
            return
          }
        }
        restart()
      },
    )
  })
  onUnmounted(() => {
    generation++
    stopRender()
    subscription?.unsubscribe()
    if (!cable) socket.disconnect()
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
    restart,
  }
}
