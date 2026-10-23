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

import { parseDashboard, serializePanel } from './dashboardParser'
import { PANEL_TYPES, panelTitle } from './panels/registry'

// One-line summary of what changed between two versions of a dashboard file,
// for Version History's audit trail: "Added Graph Temps · Edited Stat TEMP1
// · Moved 2 panels". previous is null for the first version.

function name(panel) {
  const type = PANEL_TYPES[panel.type]?.label ?? panel.originalType
  return `${type} ${panelTitle(panel)}`
}

// A panel's text without its position, to tell a move from an edit
function content(panel) {
  return serializePanel({ ...panel, x: 0, y: 0, w: 0, h: 0 })
}

function list(verb, panels) {
  if (!panels.length) return null
  if (panels.length <= 2) return `${verb} ${panels.map(name).join(', ')}`
  return `${verb} ${panels.length} panels`
}

function plural(n) {
  return `${n} panel${n === 1 ? '' : 's'}`
}

export function describeDashboardChange(previous, text) {
  const after = parseDashboard(text).model
  if (previous === null) return `Created with ${plural(after.panels.length)}`
  const before = parseDashboard(previous).model
  const parts = []
  if (before.title !== after.title) {
    parts.push(`Renamed "${before.title}" to "${after.title}"`)
  }
  if (JSON.stringify(before.settings) !== JSON.stringify(after.settings)) {
    parts.push('Changed dashboard settings')
  }
  // Pair panels up: identical text first, then the same type and title
  const unmatched = [...before.panels]
  const take = (test) => {
    const index = unmatched.findIndex(test)
    return index < 0 ? null : unmatched.splice(index, 1)[0]
  }
  const rest = after.panels.filter((panel) => {
    const lines = serializePanel(panel)
    return !take((old) => serializePanel(old) === lines)
  })
  const added = []
  const edited = []
  const moved = []
  for (const panel of rest) {
    const old = take(
      (o) => o.type === panel.type && panelTitle(o) === panelTitle(panel),
    )
    if (!old) added.push(panel)
    else if (content(old) === content(panel)) moved.push(panel)
    else edited.push(panel)
  }
  parts.push(
    ...[
      list('Added', added),
      list('Removed', unmatched),
      list('Edited', edited),
    ].filter(Boolean),
  )
  if (moved.length) parts.push(`Moved ${plural(moved.length)}`)
  return parts.join(' · ') || 'No changes to panels'
}
