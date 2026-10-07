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

const LIMIT = 100
// Changes closer together than this (typing a title) undo as one step
const COALESCE_MS = 600

// Undo / redo over serialized dashboard text, so every kind of edit (grid,
// panel dialog, code view) is covered by one mechanism
export class History {
  constructor() {
    this.state = reactive({ past: [], future: [] })
    this.current = null
    this.lastRecord = 0
  }

  reset(text) {
    this.state.past = []
    this.state.future = []
    this.current = text
    this.lastRecord = 0
  }

  get canUndo() {
    return this.state.past.length > 0
  }

  get canRedo() {
    return this.state.future.length > 0
  }

  record(text) {
    if (text === this.current) return
    const now = Date.now()
    if (now - this.lastRecord > COALESCE_MS || !this.state.past.length) {
      this.state.past.push(this.current)
      if (this.state.past.length > LIMIT) this.state.past.shift()
    }
    this.lastRecord = now
    this.current = text
    this.state.future = []
  }

  undo() {
    if (!this.canUndo) return null
    this.state.future.push(this.current)
    this.current = this.state.past.pop()
    this.lastRecord = 0
    return this.current
  }

  redo() {
    if (!this.canRedo) return null
    this.state.past.push(this.current)
    this.current = this.state.future.pop()
    this.lastRecord = 0
    return this.current
  }
}
