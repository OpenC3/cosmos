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
import { TlmPoller } from '../composables/tlmPoller'

vi.mock('@openc3/js-common/services', () => ({
  OpenC3Api: class {
    get_tlm_available = vi.fn((keys) => Promise.resolve(keys))
    get_tlm_values = vi.fn((keys) =>
      Promise.resolve(keys.map(() => [1, 'GREEN'])),
    )
  },
}))

// Lets queued microtasks, timers and the poll's awaits run
async function settle(ms = 0) {
  await vi.advanceTimersByTimeAsync(ms)
}

describe('TlmPoller', () => {
  let poller
  beforeEach(() => {
    vi.useFakeTimers()
    poller = new TlmPoller()
  })
  afterEach(() => {
    poller.stop()
    vi.useRealTimers()
  })
  const calls = () => poller.api.get_tlm_values.mock.calls.length

  it('polls once a period', async () => {
    poller.register(['A'])
    poller.start(1)
    await settle(3000)
    // The register, start, then one per second
    expect(calls()).toBeLessThanOrEqual(5)
    expect(calls()).toBeGreaterThanOrEqual(3)
  })

  it('polls right away only for keys nobody polled yet', async () => {
    poller.register(['A'])
    await settle(300)
    expect(calls()).toBe(1)
    // Another panel with the same key: already polled
    poller.register(['A'])
    await settle(300)
    expect(calls()).toBe(1)
    poller.register(['B'])
    await settle(300)
    expect(calls()).toBe(2)
  })

  it("doesn't poll early when a panel's keys change", async () => {
    poller.register(['A'])
    await settle(300)
    // e.g. a Limits panel on every limits event
    for (let i = 0; i < 10; i++) {
      poller.replace(['A'], ['A', `X${i}`])
      poller.replace(['A', `X${i}`], ['A'])
    }
    await settle(300)
    expect(calls()).toBe(1)
    expect(poller.counts.get('A')).toBe(1)
  })

  it('keeps values of keys in both lists', async () => {
    poller.register(['A', 'B'])
    await settle(300)
    expect(poller.values.A).toBeDefined()
    poller.replace(['A', 'B'], ['A', 'C'])
    expect(poller.values.A).toBeDefined()
    expect(poller.values.B).toBeUndefined()
    expect([...poller.counts.keys()]).toEqual(['A', 'C'])
  })

  it('polls new keys no more than every 250 ms', async () => {
    poller.register(['A'])
    await settle(10)
    poller.register(['B'])
    await settle(10)
    // Still within 250 ms of the first poll
    expect(calls()).toBe(1)
    await settle(300)
    expect(calls()).toBe(2)
  })
})
