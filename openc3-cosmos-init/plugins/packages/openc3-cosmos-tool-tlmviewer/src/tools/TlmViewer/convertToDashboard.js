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

// A best attempt at turning the open Telemetry Viewer screens into a
// Dashboards file: one SCREEN panel per screen, in the order they're open,
// each SCREEN_WIDTH x SCREEN_HEIGHT cells, two per row of the 12 column grid.
// Screens can be resized in the dashboard after.
const GRID_COLUMNS = 12
export const SCREEN_WIDTH = 6
export const SCREEN_HEIGHT = 10

function quote(text) {
  return `"${String(text).replaceAll('"', "'")}"`
}

// definitions: [{ target, screen }] as Telemetry Viewer keeps them
export function convertToDashboard(definitions, title) {
  const perRow = GRID_COLUMNS / SCREEN_WIDTH
  const panels = definitions.map((def, index) => {
    const x = (index % perRow) * SCREEN_WIDTH
    const y = Math.floor(index / perRow) * SCREEN_HEIGHT
    return [
      `PANEL SCREEN ${x} ${y} ${SCREEN_WIDTH} ${SCREEN_HEIGHT}`,
      `  SCREEN ${def.target} ${def.screen}`,
      'END',
    ].join('\n')
  })
  return [
    '# Converted from a Telemetry Viewer configuration',
    `DASHBOARD ${quote(title)}`,
    '',
    panels.join('\n\n'),
    '',
  ].join('\n')
}
