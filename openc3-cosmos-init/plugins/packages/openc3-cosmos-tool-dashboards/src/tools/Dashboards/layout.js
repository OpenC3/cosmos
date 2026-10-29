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

import { PANEL_TYPES } from './panels/registry'

// Grid layout rules for dashboard panels. Panels live on a 12 column grid (24
// with COLUMNS 24, for big monitors) of fixed height rows. Edits never leave overlaps or holes: a moved or resized
// panel keeps its spot, anything it lands on is pushed down, then every panel
// floats up as far as it can.

export const GRID_COLUMNS = 12
// The grid sizes a dashboard can choose (COLUMNS)
export const COLUMN_CHOICES = [12, 24]
export const ROW_HEIGHT = 40 // px, grid-auto-rows
export const GRID_GAP = 16 // px, gap
const MIN_W = 2
const MIN_H = 2
// Taller than this doesn't fit on a screen
export const MAX_H = 18

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

// Smallest size for a panel type: MIN_W x MIN_H unless the type sets its own
// `minSize` (e.g. STAT goes down to one cell, GRAPH needs 3 x 3). In columns
// either way: 24 column dashboards are for screens about twice as wide, so a
// column is about the same width.
export function minSize(type) {
  return PANEL_TYPES[type]?.minSize ?? { w: MIN_W, h: MIN_H }
}

// Keep a panel on the grid: at least its type's minSize, column so the right
// edge is <= columns. Pass `type` in the rect to get the type's minimum.
export function clampRect(rect, columns = GRID_COLUMNS) {
  const min = minSize(rect.type)
  const w = clamp(Math.round(rect.w), min.w, columns)
  const h = clamp(Math.round(rect.h), min.h, MAX_H)
  const x = clamp(Math.round(rect.x), 0, columns - w)
  const y = Math.max(0, Math.round(rect.y))
  return { x, y, w, h }
}

function collides(a, b) {
  return (
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
  )
}

// Returns new { uid: {x, y, w, h} } positions for every panel. `fixed` is the
// uid of the panel being moved or resized, which keeps its requested spot.
// `origin` is where that panel started: a panel it lands on moves into the
// vacated spot when it fits there, so dropping one panel onto another swaps
// them instead of shoving the whole dashboard down.
export function resolveLayout(
  panels,
  fixed = null,
  origin = null,
  columns = GRID_COLUMNS,
) {
  const rects = panels.map((panel) => ({
    uid: panel.uid,
    type: panel.type,
    ...clampRect(panel, columns),
  }))
  const pinned = rects.find((rect) => rect.uid === fixed)
  const others = rects
    .filter((rect) => rect !== pinned)
    .sort((a, b) => a.y - b.y || a.x - b.x)

  // Push down: place the pinned panel first, then each other panel at the
  // first row at or below its own where it doesn't collide
  const placed = pinned ? [pinned] : []
  let swapped = false
  for (const rect of others) {
    if (pinned && origin && !swapped && collides(rect, pinned)) {
      const swap = clampRect({ ...rect, x: origin.x, y: origin.y }, columns)
      if (!placed.some((other) => collides(swap, other))) {
        Object.assign(rect, swap)
        swapped = true
      }
    }
    while (placed.some((other) => collides(rect, other))) rect.y++
    placed.push(rect)
  }

  // Compact: float everything up, top to bottom. The pinned panel floats too
  // so dropping it below the last panel doesn't leave a gap.
  const ordered = [...placed].sort((a, b) => a.y - b.y || a.x - b.x)
  const settled = []
  for (const rect of ordered) {
    while (
      rect.y > 0 &&
      !settled.some((other) => collides({ ...rect, y: rect.y - 1 }, other))
    ) {
      rect.y--
    }
    settled.push(rect)
  }

  return Object.fromEntries(
    settled.map(({ uid, type: _type, ...rect }) => [uid, rect]),
  )
}

// First empty row below every rect
export function bottomRow(rects) {
  return rects.reduce((max, rect) => Math.max(max, rect.y + rect.h), 0)
}

// First spot, scanning rows top to bottom then columns left to right, where a
// panel of `type`, w x h, fits without overlapping anything
export function firstFit(panels, type, w, h, columns = GRID_COLUMNS) {
  const size = clampRect({ type, x: 0, y: 0, w, h }, columns)
  const bottom = bottomRow(panels)
  for (let y = 0; y <= bottom; y++) {
    for (let x = 0; x + size.w <= columns; x++) {
      const rect = { x, y, w: size.w, h: size.h }
      if (!panels.some((panel) => collides(rect, panel))) return rect
    }
  }
  return { x: 0, y: bottom, w: size.w, h: size.h }
}

// Pixel size of one grid cell including its gap, for converting pointer
// movement into grid units
export function cellSize(gridElement, columns = GRID_COLUMNS) {
  const width = gridElement.clientWidth
  const column = (width - GRID_GAP * (columns - 1)) / columns
  return { x: column + GRID_GAP, y: ROW_HEIGHT + GRID_GAP }
}

// Responsive layouts. Only the desktop layout is authored; tablet
// and phone layouts are derived from it, so nothing extra is saved.
const PHONE_MAX_WIDTH = 599 // px
const TABLET_MAX_WIDTH = 999 // px

export const BREAKPOINT_NOTES = {
  tablet:
    'Tablet: panels a third of the grid wide or narrower take half the width, the rest go full width.',
  phone:
    'Phone: every panel takes the full width. Side-by-side panels read left column first, then the next column.',
}

// Breakpoint for an available width in pixels
export function breakpointFor(width) {
  if (width <= PHONE_MAX_WIDTH) return 'phone'
  if (width <= TABLET_MAX_WIDTH) return 'tablet'
  return 'desktop'
}

// Place rects in reading order: each goes in the first spot at or below the
// previous one, so the derived layout reads in the same order as the desktop
function packInOrder(rects, columns) {
  const placed = []
  let row = 0
  for (const rect of rects) {
    let spot = null
    for (let y = row; !spot; y++) {
      for (let x = 0; x + rect.w <= columns; x++) {
        const candidate = { ...rect, x, y }
        if (!placed.some((other) => collides(candidate, other))) {
          spot = candidate
          break
        }
      }
    }
    placed.push(spot)
    row = spot.y
  }
  return placed
}

// Phone order: panels whose rows overlap form a band, read left to right by
// column and top to bottom within a column; a panel below everything so far
// (e.g. full width) starts the next band. So a tall panel beside a stack
// reads as the tall one, then the stack, instead of interleaving the two.
function phoneOrder(panels) {
  const ordered = []
  let band = []
  let bottom = -Infinity
  const flush = () => {
    ordered.push(...band.sort((a, b) => a.x - b.x || a.y - b.y))
    band = []
  }
  for (const panel of [...panels].sort((a, b) => a.y - b.y || a.x - b.x)) {
    if (band.length && panel.y >= bottom) flush()
    if (!band.length) bottom = -Infinity
    band.push(panel)
    bottom = Math.max(bottom, panel.y + panel.h)
  }
  flush()
  return ordered
}

// { uid: {x, y, w, h} } for the panels visible at a breakpoint
export function deriveLayout(panels, breakpoint, columns = GRID_COLUMNS) {
  if (breakpoint === 'desktop') {
    return Object.fromEntries(
      panels.map((panel) => [
        panel.uid,
        { x: panel.x, y: panel.y, w: panel.w, h: panel.h },
      ]),
    )
  }
  // Tablets pair up narrow panels (a third of the grid or less); phones give
  // every panel the full width
  const width = (panel) =>
    breakpoint === 'tablet' && panel.w <= columns / 3 ? columns / 2 : columns
  const sorted =
    breakpoint === 'phone'
      ? phoneOrder(panels)
      : [...panels].sort((a, b) => a.y - b.y || a.x - b.x)
  const ordered = sorted.map((panel) => ({
    uid: panel.uid,
    x: 0,
    y: 0,
    w: width(panel),
    h: panel.h,
  }))
  return Object.fromEntries(
    packInOrder(ordered, columns).map(({ uid, ...rect }) => [uid, rect]),
  )
}
