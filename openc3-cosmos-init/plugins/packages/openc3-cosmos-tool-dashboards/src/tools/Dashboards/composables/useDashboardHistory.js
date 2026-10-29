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

import { computed, reactive, ref } from 'vue'
import { cloneData } from './clone'
import { equal } from './equal'

const LIMIT = 100
// Changes closer together than this (typing a title) undo as one step
const COALESCE_MS = 600

// Undo / redo and unsaved changes over snapshots of the dashboard model.
// Every editor action calls commit() once it has changed the model (grid,
// panel dialog, code view, title and style), so nothing is serialized or
// compared while the model is being changed, only once per edit.
// apply(model) puts a snapshot back (undo, redo, revert).
export function useDashboardHistory(model, { apply }) {
  const state = reactive({ past: [], future: [] })
  // Not reactive: only commit, undo and redo read them
  let current = null
  let saved = null
  let lastRecord = 0
  const changed = ref(false)

  const canUndo = computed(() => state.past.length > 0)
  const canRedo = computed(() => state.future.length > 0)

  function updateChanged() {
    changed.value = saved !== null && !equal(current, saved)
  }
  // The model as saved (opened, created or just saved): nothing to save
  function markSaved() {
    saved = cloneData(model.value)
    current = saved
    changed.value = false
  }
  // Start a fresh history from the model as it is (editing starts)
  function reset() {
    state.past = []
    state.future = []
    current = cloneData(model.value)
    lastRecord = 0
  }
  function commit() {
    const next = cloneData(model.value)
    if (equal(next, current)) return
    const now = Date.now()
    if (now - lastRecord > COALESCE_MS || !state.past.length) {
      state.past.push(current)
      if (state.past.length > LIMIT) state.past.shift()
    }
    lastRecord = now
    current = next
    state.future = []
    updateChanged()
  }
  // Snapshots are copied on the way out, so later edits never change them
  function restore(snapshot) {
    current = snapshot
    lastRecord = 0
    apply(cloneData(snapshot))
    updateChanged()
  }
  function undo() {
    if (!state.past.length) return
    state.future.push(current)
    restore(state.past.pop())
  }
  function redo() {
    if (!state.future.length) return
    state.past.push(current)
    restore(state.future.pop())
  }
  // Back to the last saved model
  function revert() {
    if (saved) restore(saved)
  }

  return {
    changed,
    canUndo,
    canRedo,
    markSaved,
    reset,
    commit,
    undo,
    redo,
    revert,
  }
}
