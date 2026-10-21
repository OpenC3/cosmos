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

import { Cable } from '@openc3/js-common/services'
import { itemKey } from '../composables/tlmPoller'
import { pollType } from './tlmPanel'

const RENDER_MS = 1000

// Panels that draw their items over time. When the dashboard opens, the
// streaming API backfills the dashboard's time range (picked in the header)
// and then streams live (the way Telemetry Grapher does); during playback the
// range before the playback time is loaded instead. Use with panelBase or
// tlmPanel.
//
// Panels can override `seriesItems` (default: the panel's items) and get
// `series` ([times in seconds, then one array of values per item], oldest
// first) and `latest` (each item's newest value). About once a second
// `seriesUpdated()` is called with points older than the range dropped;
// `seriesReset()` is called whenever the series start over (by default it
// calls `seriesUpdated()`).
export default {
  inject: {
    // { seconds } from the header's time range picker
    timeRange: { default: () => ({ seconds: 120 }) },
  },
  data() {
    return { now: Date.now() / 1000 }
  },
  computed: {
    // Seconds of history shown
    duration() {
      return this.timeRange.seconds
    },
    seriesItems() {
      return this.panel.items
    },
    streamKeys() {
      return this.seriesItems.map(
        (item) => `DECOM__TLM__${itemKey(item, pollType(item))}`,
      )
    },
  },
  watch: {
    streamKeys(keys, previous) {
      if (JSON.stringify(keys) !== JSON.stringify(previous)) this.restart()
    },
    duration() {
      this.restart()
    },
    // Live streams; playback loads history around the playback time
    isPlayback() {
      this.restart()
    },
    // Stepping forward adds just the new range; anything else reloads
    playbackTime(time, previous) {
      if (!this.isPlayback || !time) return
      const forward = previous && time > previous
      if (forward && time - previous <= this.duration * 1000) {
        this.loadRange(previous, time)
      } else {
        this.restart()
      }
    },
  },
  created() {
    this.socket = this.cable || new Cable()
    this.subscription = null
    // Bumped by every restart, so a subscription still connecting from an
    // earlier one is dropped instead of streaming alongside the new one
    this.generation = 0
    this.series = [[]]
    this.latest = []
    this.renderTimer = null
  },
  mounted() {
    this.restart()
  },
  unmounted() {
    this.generation++
    this.stopRender()
    this.subscription?.unsubscribe()
    if (!this.cable) this.socket.disconnect()
  },
  methods: {
    seriesReset() {
      this.seriesUpdated()
    },
    seriesUpdated() {},
    restart() {
      const generation = ++this.generation
      this.subscription?.unsubscribe()
      this.subscription = null
      this.series = [[], ...this.seriesItems.map(() => [])]
      this.latest = this.seriesItems.map(() => null)
      this.seriesReset()
      // Nothing to draw, so no need to tick
      if (!this.seriesItems.length) {
        this.stopRender()
        return
      }
      this.renderTimer ??= setInterval(() => this.render(), RENDER_MS)
      // Playback loads the window leading up to the playback time instead
      if (this.isPlayback) {
        if (this.playbackTime) {
          this.loadRange(
            new Date(this.playbackTime.getTime() - this.duration * 1000),
            this.playbackTime,
          )
        }
        return
      }
      this.startTime = (Date.now() - this.duration * 1000) * 1_000_000
      this.needsAdd = false
      this.socket
        .createSubscription('StreamingChannel', window.openc3Scope, {
          received: (rows) => {
            if (generation !== this.generation) return
            this.socket.recordPing()
            this.append(rows)
          },
          // connected can fire before or after the promise below resolves, and
          // again after every reconnect, so both paths go through addItems
          connected: () => {
            if (generation !== this.generation) return
            this.needsAdd = true
            this.addItems()
          },
        })
        .then((subscription) => {
          if (generation !== this.generation) {
            subscription.unsubscribe()
            return
          }
          this.subscription = subscription
          this.addItems()
        })
    },
    stopRender() {
      clearInterval(this.renderTimer)
      this.renderTimer = null
    },
    addItems() {
      if (!this.subscription || !this.needsAdd) return
      this.needsAdd = false
      // Resume from the newest point we have so reconnects don't duplicate
      const last = this.series[0].at(-1)
      this.subscription.perform('add', {
        scope: window.openc3Scope,
        token: localStorage.openc3Token,
        items: this.streamKeys,
        start_time: last ? Math.floor(last * 1e9) + 1 : this.startTime,
      })
    },
    // Historical rows for playback, in the same shape the stream delivers
    async loadRange(start, end) {
      const items = this.seriesItems
      if (!items.length) return
      const timeKey = itemKey(
        { ...items[0], itemName: 'PACKET_TIMESECONDS' },
        'RAW',
      )
      const keys = [
        timeKey,
        ...items.map((item) => itemKey(item, pollType(item))),
      ]
      const poller = this.poller
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
        if (end !== this.playbackTime) return
        // One row comes back unwrapped
        const rows =
          Array.isArray(data?.[0]) && Array.isArray(data[0][0]) ? data : [data]
        this.append(
          rows
            .filter((row) => typeof row?.[0]?.[0] === 'number')
            .map((row) =>
              Object.fromEntries([
                ['__time', row[0][0] * 1e9],
                ...this.streamKeys.map((key, i) => [key, row[i + 1]?.[0]]),
              ]),
            ),
        )
        this.render()
      } catch (error) {
        console.error('Dashboards playback history failed:', error)
      } finally {
        poller.clock.loading--
      }
    },
    append(rows) {
      const [xs, ...ys] = this.series
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
        this.streamKeys.forEach((key, i) => {
          if (key in row) {
            const value = typeof row[key] === 'number' ? row[key] : null
            ys[i][index] = value
            if (value !== null && index === xs.length - 1)
              this.latest[i] = value
          }
        })
      }
    },
    render() {
      this.now = (this.playbackTime?.getTime() ?? Date.now()) / 1000
      // Drop points that scrolled off the left edge
      const cutoff = this.now - this.duration
      const xs = this.series[0]
      let drop = 0
      while (drop < xs.length && xs[drop] < cutoff) drop++
      if (drop > 0) this.series.forEach((series) => series.splice(0, drop))
      this.seriesUpdated()
    },
  },
}
