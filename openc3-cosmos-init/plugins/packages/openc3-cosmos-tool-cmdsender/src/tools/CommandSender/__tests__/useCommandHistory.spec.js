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

import { describe, expect, it } from 'vitest'
import { effectScope } from 'vue'
import {
  HISTORY_KEY,
  LEGACY_HISTORY_KEY,
  MAX_HISTORY,
  addEntry,
  loadHistory,
  useCommandHistory,
} from '../useCommandHistory'

// The localStorage interface, in memory
function memoryStorage(initial = {}) {
  const data = { ...initial }
  return {
    data,
    getItem: (key) => (key in data ? data[key] : null),
    setItem: (key, value) => {
      data[key] = String(value)
    },
    removeItem: (key) => {
      delete data[key]
    },
  }
}

describe('loadHistory', () => {
  it('starts empty', () => {
    expect(loadHistory(memoryStorage())).toEqual([])
  })

  it('reads saved entries', () => {
    const saved = [
      { cmd: 'cmd("INST ABORT")', sentAt: 2 },
      { cmd: 'cmd("INST CLEAR")', sentAt: 1 },
    ]
    const storage = memoryStorage({ [HISTORY_KEY]: JSON.stringify(saved) })
    expect(loadHistory(storage)).toEqual(saved)
  })

  it('migrates the old editor history, one entry per line', () => {
    const storage = memoryStorage({
      [LEGACY_HISTORY_KEY]: 'cmd("INST ABORT")\n\n  cmd("INST CLEAR")  \n',
    })
    expect(loadHistory(storage)).toEqual([
      { cmd: 'cmd("INST ABORT")', sentAt: null },
      { cmd: 'cmd("INST CLEAR")', sentAt: null },
    ])
    expect(storage.data[LEGACY_HISTORY_KEY]).toBeUndefined()
    expect(JSON.parse(storage.data[HISTORY_KEY])).toHaveLength(2)
  })

  it('prefers the new history over the old one', () => {
    const storage = memoryStorage({
      [HISTORY_KEY]: JSON.stringify([{ cmd: 'cmd("INST ABORT")', sentAt: 1 }]),
      [LEGACY_HISTORY_KEY]: 'cmd("INST CLEAR")',
    })
    expect(loadHistory(storage)).toEqual([
      { cmd: 'cmd("INST ABORT")', sentAt: 1 },
    ])
  })

  it('drops corrupt data instead of failing', () => {
    expect(loadHistory(memoryStorage({ [HISTORY_KEY]: '{not json' }))).toEqual(
      [],
    )
    expect(
      loadHistory(
        memoryStorage({
          [HISTORY_KEY]: JSON.stringify([{ cmd: 'ok', sentAt: 1 }, 5, {}]),
        }),
      ),
    ).toEqual([{ cmd: 'ok', sentAt: 1 }])
  })

  it('drops saved data that is not a list and fixes bad times', () => {
    expect(
      loadHistory(memoryStorage({ [HISTORY_KEY]: '{"cmd":"x"}' })),
    ).toEqual([])
    expect(
      loadHistory(
        memoryStorage({
          [HISTORY_KEY]: JSON.stringify([{ cmd: 'ok', sentAt: 'yesterday' }]),
        }),
      ),
    ).toEqual([{ cmd: 'ok', sentAt: null }])
  })

  it('works without storage, e.g. when the browser blocks it', () => {
    const blocked = {
      getItem: () => {
        throw new Error('SecurityError')
      },
    }
    expect(loadHistory(blocked)).toEqual([])
  })
})

describe('addEntry', () => {
  it('puts the newest entry first and keeps repeats', () => {
    let entries = addEntry([], 'cmd("INST ABORT")', 1)
    entries = addEntry(entries, 'cmd("INST CLEAR")', 2)
    entries = addEntry(entries, 'cmd("INST ABORT")', 3)
    expect(entries.map((e) => [e.cmd, e.sentAt])).toEqual([
      ['cmd("INST ABORT")', 3],
      ['cmd("INST CLEAR")', 2],
      ['cmd("INST ABORT")', 1],
    ])
  })

  it(`keeps the newest ${MAX_HISTORY}`, () => {
    let entries = []
    for (let i = 0; i < MAX_HISTORY + 5; i++) {
      entries = addEntry(entries, `cmd("INST ${i}")`, i)
    }
    expect(entries).toHaveLength(MAX_HISTORY)
    expect(entries[0].sentAt).toBe(MAX_HISTORY + 4)
    expect(entries.at(-1).sentAt).toBe(5)
  })
})

describe('useCommandHistory', () => {
  it('adds, saves and clears', () => {
    const storage = memoryStorage()
    const scope = effectScope()
    const history = scope.run(() => useCommandHistory(storage))
    history.add('cmd("INST ABORT")')
    history.add('cmd("INST ABORT")')
    expect(history.entries.value).toHaveLength(2)
    expect(JSON.parse(storage.data[HISTORY_KEY])).toHaveLength(2)
    // Each entry has its own id, even for the same command
    const [first, second] = history.entries.value
    expect(first.id).not.toBe(second.id)
    history.clear()
    expect(history.entries.value).toEqual([])
    expect(storage.data[HISTORY_KEY]).toBeUndefined()
    scope.stop()
  })

  it('works outside a component, without cleanup', () => {
    const storage = memoryStorage()
    const history = useCommandHistory(storage, null)
    history.add('cmd("INST ABORT")')
    expect(history.entries.value).toHaveLength(1)
  })

  it('works when reading localStorage itself throws', () => {
    const descriptor = Object.getOwnPropertyDescriptor(
      globalThis,
      'localStorage',
    )
    Object.defineProperty(globalThis, 'localStorage', {
      configurable: true,
      get() {
        throw new Error('SecurityError')
      },
    })
    try {
      const scope = effectScope()
      const history = scope.run(() => useCommandHistory(undefined, null))
      history.add('cmd("INST ABORT")')
      expect(history.entries.value).toHaveLength(1)
      history.clear()
      expect(history.entries.value).toEqual([])
      scope.stop()
    } finally {
      if (descriptor) {
        Object.defineProperty(globalThis, 'localStorage', descriptor)
      } else {
        delete globalThis.localStorage
      }
    }
  })

  it('keeps working when saving fails', () => {
    const storage = memoryStorage()
    storage.setItem = () => {
      throw new Error('QuotaExceededError')
    }
    const scope = effectScope()
    const history = scope.run(() => useCommandHistory(storage))
    history.add('cmd("INST ABORT")')
    expect(history.entries.value).toHaveLength(1)
    scope.stop()
  })

  it('picks up history saved by another tab', () => {
    const storage = memoryStorage()
    const listeners = []
    const target = {
      addEventListener: (type, fn) => listeners.push([type, fn]),
      removeEventListener: (type, fn) => {
        const i = listeners.findIndex(([t, f]) => t === type && f === fn)
        listeners.splice(i, 1)
      },
    }
    const scope = effectScope()
    const history = scope.run(() => useCommandHistory(storage, target))
    storage.setItem(
      HISTORY_KEY,
      JSON.stringify([{ cmd: 'cmd("INST CLEAR")', sentAt: 9 }]),
    )
    const storageEvent = (key) => {
      for (const [type, fn] of listeners) {
        if (type === 'storage') fn({ key })
      }
    }
    // Another key changing is ignored
    storageEvent('some_other_key')
    expect(history.entries.value).toEqual([])
    storageEvent(HISTORY_KEY)
    expect(history.entries.value.map((e) => e.cmd)).toEqual([
      'cmd("INST CLEAR")',
    ])
    // localStorage.clear() in another tab sends a null key
    storage.removeItem(HISTORY_KEY)
    storageEvent(null)
    expect(history.entries.value).toEqual([])
    scope.stop()
    expect(listeners).toHaveLength(0)
  })
})
