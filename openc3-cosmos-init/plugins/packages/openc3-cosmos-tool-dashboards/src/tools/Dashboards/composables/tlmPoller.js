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

import { reactive } from 'vue'
import { OpenC3Api } from '@openc3/js-common/services'

// TGT__PKT__ITEM, the identity of an item regardless of value type
export function baseKey(item) {
  return `${item.targetName}__${item.packetName}__${item.itemName}`
}

// TGT__PKT__ITEM__TYPE as used by get_tlm_values
export function itemKey(item, valueType = item.valueType || 'CONVERTED') {
  return `${baseKey(item)}__${valueType}`
}

// Received time of the packet an item comes from
export function packetTimeKey(item) {
  return itemKey({ ...item, itemName: 'PACKET_TIMEFORMATTED' }, 'CONVERTED')
}

function sameValue(a, b) {
  if (a === b) return true
  // Arrays, binary strings and NaN/Infinity arrive as objects
  return (
    typeof a === 'object' &&
    typeof b === 'object' &&
    JSON.stringify(a) === JSON.stringify(b)
  )
}

// One poller per dashboard. Panels register the item keys they display and
// read results from `values`, so the whole dashboard makes a single
// get_tlm_values request per period no matter how many panels it has.
export class TlmPoller {
  constructor(periodSeconds = 1) {
    this.api = new OpenC3Api()
    // requested key => { value, state, changedAt }. An entry is only replaced
    // when its value or state changes, so unchanged items don't re-render.
    this.values = reactive({})
    // tick: bumped after every poll, for panels that sample over time.
    // loading: requests in flight, so playback waits before stepping on.
    this.clock = reactive({ tick: 0, loading: 0 })
    // In playback, values are looked up as of this Date instead of polled
    this.playbackTime = null
    this.counts = new Map()
    // requested key => key from get_tlm_available (null if the item is unknown)
    this.available = {}
    this.period = periodSeconds
    this.timer = null
    this.busy = false
    this.pending = false
    // Paused while a dashboard is being edited: nothing is fetched
    this.paused = false
  }

  pause() {
    this.paused = true
  }

  resume() {
    this.paused = false
    this.poll()
  }

  register(keys) {
    for (const key of keys) {
      this.counts.set(key, (this.counts.get(key) || 0) + 1)
    }
    this.schedule()
  }

  unregister(keys) {
    for (const key of keys) {
      const count = (this.counts.get(key) || 0) - 1
      if (count > 0) {
        this.counts.set(key, count)
      } else {
        this.counts.delete(key)
        delete this.values[key]
      }
    }
  }

  // Panels mount one after another; batch their registrations into one poll
  schedule() {
    if (this.scheduled) return
    this.scheduled = true
    queueMicrotask(() => {
      this.scheduled = false
      this.poll()
    })
  }

  start(periodSeconds = this.period) {
    this.stop()
    this.period = Math.max(0.1, periodSeconds)
    // Playback fetches when its time changes, not on a timer
    if (this.playbackTime) return
    this.timer = setInterval(() => this.poll(), this.period * 1000)
    this.poll()
  }

  // Show values as of `time` (a Date); null goes back to live polling
  setPlaybackTime(time) {
    const wasLive = !this.playbackTime
    this.playbackTime = time
    if (time) {
      this.stop()
      this.poll()
    } else if (!wasLive) {
      this.start()
    }
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  async resolve(keys) {
    const unknown = keys.filter((key) => !(key in this.available))
    if (unknown.length === 0) return
    const result = await this.api.get_tlm_available(
      unknown,
      {},
      { 'Ignore-Errors': '404' },
    )
    unknown.forEach((key, index) => {
      this.available[key] = result?.[index] ?? null
    })
  }

  async poll() {
    if (this.paused || this.counts.size === 0) return
    if (this.busy) {
      // Run again when the current poll finishes so new keys aren't skipped
      this.pending = true
      return
    }
    this.busy = true
    this.clock.loading++
    try {
      const requested = [...this.counts.keys()]
      await this.resolve(requested)
      const keys = requested.filter((key) => this.available[key])
      if (keys.length === 0) return
      const time = this.playbackTime
      const results = await this.api.get_tlm_values(
        keys.map((key) => this.available[key]),
        30, // stale time
        time ? null : 0.1, // cache timeout
        time, // playback: values as of this time
        null,
        { 'Ignore-Errors': '403' },
      )
      // The time just switched (back to live, or to another moment) while
      // this was loading; its results are for the wrong time
      if (time !== this.playbackTime) return
      const now = time ? time.getTime() : Date.now()
      keys.forEach((key, index) => {
        const [value, state] = results[index] || []
        const previous = this.values[key]
        if (!previous) {
          // changedAt stays null until a change is actually seen, so panels
          // don't report the time the dashboard opened as a state change
          this.values[key] = { value, state, changedAt: null }
        } else if (
          !sameValue(previous.value, value) ||
          previous.state !== state
        ) {
          this.values[key] = { value, state, changedAt: now }
        }
      })
      this.clock.tick++
    } catch (error) {
      // Transient errors are retried on the next period
      console.error('Dashboards telemetry poll failed:', error)
    } finally {
      this.busy = false
      this.clock.loading--
      if (this.pending) {
        this.pending = false
        this.poll()
      }
    }
  }
}
