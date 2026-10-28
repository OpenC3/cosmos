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

import { effectScope, reactive, watch } from 'vue'
import { Cable } from '@openc3/js-common/services'

const TICK_MS = 1000

// 'DECOM__TLM__TGT__PKT__ITEM__TYPE' -> { target, packet, pollKey }
function parseKey(key) {
  const [, , target, packet, item, type] = key.split('__')
  return { target, packet, pollKey: `${target}__${packet}__${item}__${type}` }
}

// Telemetry history for every graph and sparkline on a dashboard, like the
// poller is for current values: panels acquire the stream keys they draw
// and share one StreamingChannel subscription, one backfill per item and
// one clock, however many panels show the same item.
//
// Each key keeps its own times (seconds) and values, oldest first, trimmed
// to the dashboard's time range. They're plain arrays updated in place;
// `state.version` is bumped once a second (and on changes) so panels know
// to redraw, and `state.now` is the end of the window (the playback time
// during playback). Listeners added with onTick run after each bump.
export class SeriesStore {
  // timeRange: { seconds }, timeline: { on, time } (both reactive)
  constructor({ poller, cable = null, timeRange, timeline }) {
    this.poller = poller
    this.socket = cable || new Cable()
    this.ownSocket = !cable
    this.timeRange = timeRange
    this.timeline = timeline
    // key => { refs, times, values, latest }
    this.entries = new Map()
    this.state = reactive({ now: Date.now() / 1000, version: 0 })
    this.listeners = new Set()
    this.subscription = null
    this.subscribing = false
    this.connected = false
    // Set on every (re)connect: all keys are (re)added once the
    // subscription is ready, which can be before or after it connects
    this.needsResume = false
    // Bumped by every restart, so a subscription still connecting from an
    // earlier one is dropped instead of streaming alongside the new one
    this.generation = 0
    this.pending = new Set()
    this.flushQueued = false
    this.timer = setInterval(() => this.tick(), TICK_MS)
    // The stream lives outside Vue: start over when the window or playback
    // changes, and step forward through playback without reloading
    this.scope = effectScope(true)
    this.scope.run(() => {
      watch(
        () => [this.timeRange.seconds, this.timeline.on],
        () => this.restart(),
      )
      watch(
        () => (this.timeline.on ? this.timeline.time : null),
        (time, previous) => this.playbackMoved(time, previous),
      )
    })
  }

  get duration() {
    return this.timeRange.seconds
  }

  get playbackTime() {
    return this.timeline.on ? this.timeline.time : null
  }

  // The arrays for a key ({ times, values, latest }), or null
  get(key) {
    return this.entries.get(key) ?? null
  }

  // Call when the panel draws these keys; release them when it stops
  acquire(keys) {
    for (const key of keys) {
      const entry = this.entries.get(key)
      if (entry) {
        entry.refs++
        continue
      }
      this.entries.set(key, { refs: 1, times: [], values: [], latest: null })
      this.pending.add(key)
    }
    this.queueFlush()
  }

  release(keys) {
    // Panels release as the dashboard unmounts, after dispose: nothing to
    // tell a stream that's gone
    if (this.disposed) return
    const removed = []
    for (const key of keys) {
      const entry = this.entries.get(key)
      if (!entry) continue
      if (--entry.refs > 0) continue
      this.entries.delete(key)
      this.pending.delete(key)
      removed.push(key)
    }
    if (removed.length && !this.timeline.on) {
      this.perform('remove', { items: removed })
    }
  }

  // Runs fn() after every redraw tick; returns a function that removes it
  onTick(fn) {
    this.listeners.add(fn)
    return () => this.listeners.delete(fn)
  }

  dispose() {
    this.disposed = true
    this.generation++
    clearInterval(this.timer)
    this.scope.stop()
    close(this.subscription)
    this.subscription = null
    if (this.ownSocket) this.socket.disconnect()
    this.listeners.clear()
  }

  // Panels mount one after another; start their keys in one request
  queueFlush() {
    if (this.flushQueued) return
    this.flushQueued = true
    queueMicrotask(() => {
      this.flushQueued = false
      this.flush()
    })
  }

  flush() {
    if (!this.pending.size) return
    const keys = [...this.pending]
    if (this.timeline.on) {
      this.pending.clear()
      const end = this.playbackTime
      if (end) this.loadRange(keys, this.windowStart(end), end)
      return
    }
    if (!this.subscription) {
      // Connecting adds every key, these included
      if (!this.subscribing) this.subscribe()
      return
    }
    if (!this.connected) return
    this.pending.clear()
    this.addToStream(keys, this.windowStart(new Date()))
  }

  windowStart(end) {
    return new Date(end.getTime() - this.duration * 1000)
  }

  restart() {
    this.generation++
    close(this.subscription)
    this.subscription = null
    this.subscribing = false
    this.connected = false
    this.needsResume = false
    for (const [key, entry] of this.entries) {
      entry.times.length = 0
      entry.values.length = 0
      entry.latest = null
      this.pending.add(key)
    }
    this.tick()
    this.queueFlush()
  }

  // Stepping forward adds just the new range; anything else reloads
  playbackMoved(time, previous) {
    if (!time) return
    const step = previous ? time - previous : 0
    if (step > 0 && step <= this.duration * 1000) {
      this.loadRange([...this.entries.keys()], previous, time)
    } else {
      this.restart()
    }
  }

  subscribe() {
    const generation = this.generation
    this.subscribing = true
    this.socket
      .createSubscription('StreamingChannel', window.openc3Scope, {
        received: (rows) => {
          if (generation !== this.generation) return
          this.socket.recordPing()
          this.append(rows)
        },
        // Fires on every (re)connect: add everything, resuming from the
        // newest point held so reconnects don't refetch the whole window
        connected: () => {
          if (generation !== this.generation) return
          this.connected = true
          this.needsResume = true
          this.tryResume()
        },
        disconnected: () => {
          this.connected = false
        },
      })
      .then((subscription) => {
        if (generation !== this.generation) {
          close(subscription)
          return
        }
        this.subscription = subscription
        this.subscribing = false
        this.tryResume()
      })
  }

  tryResume() {
    if (!this.subscription || !this.connected || !this.needsResume) return
    this.needsResume = false
    this.pending.clear()
    this.resume()
  }

  resume() {
    const keys = [...this.entries.keys()]
    if (!keys.length || !this.subscription) return
    const start = this.windowStart(new Date())
    let from = Infinity
    for (const key of keys) {
      const last = this.entries.get(key).times.at(-1)
      from = Math.min(from, last ? last * 1000 : start.getTime())
    }
    this.addToStream(keys, new Date(Math.max(from, start.getTime())))
  }

  addToStream(keys, start) {
    if (!keys.length) return
    this.perform('add', {
      items: keys,
      start_time: start.getTime() * 1_000_000,
    })
  }

  // perform() waits for the subscription and rejects if it closed in the
  // meantime, e.g. the panels' removes as the whole grid unmounts. The
  // stream is going away then, so that's not an error.
  perform(action, data) {
    this.subscription
      ?.perform(action, {
        scope: window.openc3Scope,
        token: localStorage.openc3Token,
        ...data,
      })
      ?.catch?.(() => {})
  }

  // Historical values for playback, per packet so each item is timed by
  // its own packet
  async loadRange(keys, start, end) {
    const generation = this.generation
    const packets = new Map()
    for (const key of keys) {
      const { target, packet, pollKey } = parseKey(key)
      const id = `${target}__${packet}`
      if (!packets.has(id)) packets.set(id, [])
      packets.get(id).push({ key, pollKey })
    }
    const poller = this.poller
    poller.clock.loading++
    try {
      await Promise.all(
        [...packets].map(async ([id, items]) => {
          const pollKeys = [
            `${id}__PACKET_TIMESECONDS__RAW`,
            ...items.map((item) => item.pollKey),
          ]
          await poller.resolve(pollKeys)
          const data = await poller.api.get_tlm_values(
            pollKeys.map((key) => poller.available[key]),
            30,
            null,
            start,
            end,
            { 'Ignore-Errors': '403' },
          )
          // The window moved on while this loaded
          if (generation !== this.generation || end !== this.playbackTime) {
            return
          }
          // One row comes back unwrapped
          const rows =
            Array.isArray(data?.[0]) && Array.isArray(data[0][0])
              ? data
              : [data]
          this.append(
            rows
              .filter((row) => typeof row?.[0]?.[0] === 'number')
              .map((row) =>
                Object.fromEntries([
                  ['__time', row[0][0] * 1e9],
                  ...items.map((item, i) => [item.key, row[i + 1]?.[0]]),
                ]),
              ),
          )
        }),
      )
      if (generation === this.generation) this.tick()
    } catch (error) {
      console.error('Dashboards playback history failed:', error)
    } finally {
      poller.clock.loading--
    }
  }

  // Rows as the stream delivers them: { __time (ns), key: value, ... }
  append(rows) {
    for (const row of rows) {
      if (!row.__time) continue
      const t = row.__time / 1e9
      for (const key in row) {
        if (key === '__time') continue
        const entry = this.entries.get(key)
        if (!entry) continue
        const value = typeof row[key] === 'number' ? row[key] : null
        insert(entry, t, value)
      }
    }
  }

  tick() {
    this.state.now = (this.playbackTime?.getTime() ?? Date.now()) / 1000
    // Drop points that scrolled off the left edge
    const cutoff = this.state.now - this.duration
    for (const entry of this.entries.values()) {
      let drop = 0
      while (drop < entry.times.length && entry.times[drop] < cutoff) drop++
      if (drop) {
        entry.times.splice(0, drop)
        entry.values.splice(0, drop)
      }
    }
    this.state.version++
    for (const fn of this.listeners) fn()
  }
}

// unsubscribe() also rejects when the subscription already closed, which
// is the state we want anyway
function close(subscription) {
  subscription?.unsubscribe()?.catch?.(() => {})
}

// Points mostly arrive in order; the same time again replaces the value
function insert(entry, t, value) {
  const { times, values } = entry
  let index = times.length
  while (index > 0 && times[index - 1] > t) index--
  if (index > 0 && times[index - 1] === t) {
    values[index - 1] = value
  } else {
    times.splice(index, 0, t)
    values.splice(index, 0, value)
  }
  if (value !== null && index >= times.length - 1) entry.latest = value
}

// The keys' series on one time axis, the shape uPlot draws:
// [times, values of the first key, ...], null where a key has no point
export function alignSeries(entries) {
  if (entries.length === 1) {
    const entry = entries[0]
    return entry ? [entry.times, entry.values] : [[], []]
  }
  const times = []
  const seen = new Set()
  for (const entry of entries) {
    for (const t of entry?.times ?? []) {
      if (!seen.has(t)) {
        seen.add(t)
        times.push(t)
      }
    }
  }
  times.sort((a, b) => a - b)
  const index = new Map(times.map((t, i) => [t, i]))
  const columns = entries.map((entry) => {
    const column = new Array(times.length).fill(null)
    if (entry) {
      entry.times.forEach((t, i) => {
        column[index.get(t)] = entry.values[i]
      })
    }
    return column
  })
  return [times, ...columns]
}
