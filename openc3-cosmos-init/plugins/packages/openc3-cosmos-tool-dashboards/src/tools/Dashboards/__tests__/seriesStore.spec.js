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

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { reactive } from 'vue'
import { SeriesStore, alignSeries } from '../composables/seriesStore'

const A = 'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'
const B = 'DECOM__TLM__INST__ADCS__POSX__CONVERTED'

function makeStore() {
  const subscription = { perform: vi.fn(), unsubscribe: vi.fn() }
  const cable = {
    createSubscription: vi.fn(() => Promise.resolve(subscription)),
    recordPing: vi.fn(),
  }
  const store = new SeriesStore({
    poller: { clock: { loading: 0 } },
    cable,
    timeRange: reactive({ seconds: 120 }),
    timeline: reactive({ on: false, time: null }),
  })
  return { store, cable, subscription }
}

let stores = []
beforeEach(() => {
  // The store reads the scope and token the COSMOS page sets
  vi.stubGlobal('window', { openc3Scope: 'DEFAULT' })
  vi.stubGlobal('localStorage', { openc3Token: 'token' })
})
afterEach(() => {
  vi.unstubAllGlobals()
  stores.forEach((store) => store.dispose())
  stores = []
  vi.useRealTimers()
})

describe('alignSeries', () => {
  it('returns one series as is, without copying', () => {
    const entry = { times: [1, 2], values: [10, 20] }
    const [times, values] = alignSeries([entry])
    expect(times).toBe(entry.times)
    expect(values).toBe(entry.values)
  })

  it('puts several series on one time axis with nulls in the gaps', () => {
    const a = { times: [1, 3], values: [10, 30] }
    const b = { times: [2, 3], values: [200, 300] }
    expect(alignSeries([a, b])).toEqual([
      [1, 2, 3],
      [10, null, 30],
      [null, 200, 300],
    ])
  })

  it('treats a missing entry as empty', () => {
    expect(alignSeries([null])).toEqual([[], []])
    expect(alignSeries([{ times: [1], values: [5] }, null])).toEqual([
      [1],
      [5],
      [null],
    ])
  })
})

describe('SeriesStore', () => {
  it('keeps each key in time order and replaces repeated times', () => {
    const { store } = makeStore()
    stores.push(store)
    store.acquire([A, B])
    store.append([
      { __time: 2e9, [A]: 2 },
      { __time: 1e9, [A]: 1, [B]: 100 },
      { __time: 2e9, [A]: 22 },
      { __time: 3e9, [B]: 'text' },
    ])
    expect(store.get(A).times).toEqual([1, 2])
    expect(store.get(A).values).toEqual([1, 22])
    expect(store.get(A).latest).toBe(22)
    // Non numbers are kept as gaps
    expect(store.get(B).values).toEqual([100, null])
    expect(store.get(B).latest).toBe(100)
  })

  it('stores NaN and infinities as gaps, since they cannot be drawn', () => {
    const { store } = makeStore()
    stores.push(store)
    store.acquire([A])
    store.append([
      { __time: 1e9, [A]: 1 },
      { __time: 2e9, [A]: Number.NaN },
      { __time: 3e9, [A]: Number.POSITIVE_INFINITY },
    ])
    expect(store.get(A).values).toEqual([1, null, null])
    expect(store.get(A).latest).toBe(1)
  })

  it('ignores rows for keys nobody acquired', () => {
    const { store } = makeStore()
    stores.push(store)
    store.acquire([A])
    store.append([{ __time: 1e9, [B]: 5 }])
    expect(store.get(B)).toBeNull()
  })

  it('counts references and removes a key when the last panel releases it', () => {
    const { store } = makeStore()
    stores.push(store)
    store.acquire([A])
    store.acquire([A])
    store.release([A])
    expect(store.get(A)).not.toBeNull()
    store.release([A])
    expect(store.get(A)).toBeNull()
  })

  it('drops points older than the time range on each tick', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(1000 * 1000))
    const { store } = makeStore()
    stores.push(store)
    store.acquire([A])
    store.append([
      { __time: 800 * 1e9, [A]: 1 },
      { __time: 950 * 1e9, [A]: 2 },
    ])
    const listener = vi.fn()
    store.onTick(listener)
    const version = store.state.version
    store.tick()
    expect(store.get(A).times).toEqual([950])
    expect(store.state.now).toBe(1000)
    expect(store.state.version).toBe(version + 1)
    expect(listener).toHaveBeenCalledOnce()
  })

  it('shares one subscription across panels and adds every key once connected', async () => {
    const { store, cable, subscription } = makeStore()
    stores.push(store)
    store.acquire([A])
    store.acquire([B])
    await Promise.resolve()
    await Promise.resolve()
    expect(cable.createSubscription).toHaveBeenCalledOnce()
    // Connected fires on the channel's callbacks
    cable.createSubscription.mock.calls[0][2].connected()
    await Promise.resolve()
    const adds = subscription.perform.mock.calls.filter(
      ([action]) => action === 'add',
    )
    expect(adds).toHaveLength(1)
    expect(adds[0][1].items.sort()).toEqual([A, B].sort())
  })
})
