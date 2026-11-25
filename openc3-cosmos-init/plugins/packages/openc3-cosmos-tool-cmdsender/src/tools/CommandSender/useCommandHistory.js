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

import { getCurrentScope, onScopeDispose, ref } from 'vue'

// The commands sent from Command Sender, newest first, one entry per send.
// Kept in localStorage so it survives reloads; each browser has its own.
export const HISTORY_KEY = 'command_sender__history_v2'
// The old editable history stored the editor text, one command a line
export const LEGACY_HISTORY_KEY = 'command_sender__history'
export const MAX_HISTORY = 500

// Saved entries are { cmd, sentAt }: the command as scripted and the time it
// was sent in ms, or null for history migrated from the old editor
export function loadHistory(storage) {
  try {
    const saved = storage.getItem(HISTORY_KEY)
    if (saved !== null) {
      const parsed = JSON.parse(saved)
      if (!Array.isArray(parsed)) return []
      return parsed
        .filter((entry) => typeof entry?.cmd === 'string')
        .map(({ cmd, sentAt }) => ({
          cmd,
          sentAt: typeof sentAt === 'number' ? sentAt : null,
        }))
        .slice(0, MAX_HISTORY)
    }
    const legacy = storage.getItem(LEGACY_HISTORY_KEY)
    if (legacy === null) return []
    const entries = legacy
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line !== '')
      .slice(0, MAX_HISTORY)
      .map((cmd) => ({ cmd, sentAt: null }))
    storage.setItem(HISTORY_KEY, JSON.stringify(entries))
    storage.removeItem(LEGACY_HISTORY_KEY)
    return entries
  } catch {
    // Storage is blocked (e.g. private windows) or the data is corrupt
    return []
  }
}

export function addEntry(entries, cmd, sentAt = Date.now()) {
  return [{ cmd, sentAt }, ...entries].slice(0, MAX_HISTORY)
}

// localStorage, or null where reading it throws (e.g. a sandboxed frame or
// blocked site data); the history then only lasts until the page closes
function defaultStorage() {
  try {
    return globalThis.localStorage ?? null
  } catch {
    return null
  }
}

// entries are the saved entries plus an id (for list keys and selection)
// that is only unique within this page
export function useCommandHistory(
  storage = defaultStorage(),
  eventTarget = globalThis.window,
) {
  let nextId = 1
  const withId = (entry) => ({ ...entry, id: nextId++ })
  const entries = ref(loadHistory(storage).map(withId))

  function save() {
    try {
      storage.setItem(
        HISTORY_KEY,
        JSON.stringify(
          entries.value.map(({ cmd, sentAt }) => ({ cmd, sentAt })),
        ),
      )
    } catch {
      // Full or blocked: the history still works until the page is closed
    }
  }

  function add(cmd) {
    const [entry, ...rest] = addEntry(entries.value, cmd)
    entries.value = [withId(entry), ...rest]
    save()
  }

  function clear() {
    entries.value = []
    try {
      storage.removeItem(HISTORY_KEY)
    } catch {
      // Blocked storage, nothing was saved
    }
  }

  // Another Command Sender tab sent a command (or cleared the history).
  // Take its history so this tab doesn't overwrite it on the next send.
  function storageChanged(event) {
    if (event.key === HISTORY_KEY || event.key === null) {
      entries.value = loadHistory(storage).map(withId)
    }
  }
  eventTarget?.addEventListener('storage', storageChanged)
  if (getCurrentScope()) {
    onScopeDispose(() => {
      eventTarget?.removeEventListener('storage', storageChanged)
    })
  }

  return { entries, add, clear }
}
