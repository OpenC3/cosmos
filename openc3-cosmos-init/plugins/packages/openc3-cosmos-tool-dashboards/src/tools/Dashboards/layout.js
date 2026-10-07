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

// Grid layout rules for dashboard panels. Panels live on a 12 column grid of
// fixed height rows. Edits never leave overlaps or holes: a moved or resized
// panel keeps its spot, anything it lands on is pushed down, then every panel
// floats up as far as it can.

export const GRID_COLUMNS = 12
export const ROW_HEIGHT = 40 // px, grid-auto-rows
export const GRID_GAP = 16 // px, gap
export const MIN_W = 2
export const MIN_H = 2
// Taller than this doesn't fit on a screen
export const MAX_H = 18

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

// Keep a panel on the grid: width 2..12, column so the right edge is <= 12
export function clampRect(rect) {
  const w = clamp(Math.round(rect.w), MIN_W, GRID_COLUMNS)
  const h = clamp(Math.round(rect.h), MIN_H, MAX_H)
  const x = clamp(Math.round(rect.x), 0, GRID_COLUMNS - w)
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
export function resolveLayout(panels, fixed = null, origin = null) {
  const rects = panels.map((panel) => ({ uid: panel.uid, ...clampRect(panel) }))
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
      const swap = clampRect({ ...rect, x: origin.x, y: origin.y })
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

  return Object.fromEntries(settled.map(({ uid, ...rect }) => [uid, rect]))
}

// First empty row below every rect
export function bottomRow(rects) {
  return rects.reduce((max, rect) => Math.max(max, rect.y + rect.h), 0)
}

// First spot, scanning rows top to bottom then columns left to right, where a
// w x h panel fits without overlapping anything
export function firstFit(panels, w, h) {
  const size = clampRect({ x: 0, y: 0, w, h })
  const bottom = bottomRow(panels)
  for (let y = 0; y <= bottom; y++) {
    for (let x = 0; x + size.w <= GRID_COLUMNS; x++) {
      const rect = { x, y, w: size.w, h: size.h }
      if (!panels.some((panel) => collides(rect, panel))) return rect
    }
  }
  return { x: 0, y: bottom, w: size.w, h: size.h }
}

// Pixel size of one grid cell including its gap, for converting pointer
// movement into grid units
export function cellSize(gridElement) {
  const width = gridElement.clientWidth
  const column = (width - GRID_GAP * (GRID_COLUMNS - 1)) / GRID_COLUMNS
  return { x: column + GRID_GAP, y: ROW_HEIGHT + GRID_GAP }
}

// Responsive layouts. Only the desktop (12 column) layout is authored; tablet
// and phone layouts are derived from it, so nothing extra is saved.
export const PHONE_MAX_WIDTH = 599 // px
export const TABLET_MAX_WIDTH = 999 // px

export const BREAKPOINT_NOTES = {
  tablet:
    'Tablet: panels 4 columns or narrower take half the width, the rest go full width.',
  phone: 'Phone: every panel takes the full width, in reading order.',
}

// Breakpoint for an available width in pixels
export function breakpointFor(width) {
  if (width <= PHONE_MAX_WIDTH) return 'phone'
  if (width <= TABLET_MAX_WIDTH) return 'tablet'
  return 'desktop'
}

// Place rects in reading order: each goes in the first spot at or below the
// previous one, so the derived layout reads in the same order as the desktop
function packInOrder(rects) {
  const placed = []
  let row = 0
  for (const rect of rects) {
    let spot = null
    for (let y = row; !spot; y++) {
      for (let x = 0; x + rect.w <= GRID_COLUMNS; x++) {
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

// { uid: {x, y, w, h} } for the panels visible at a breakpoint
export function deriveLayout(panels, breakpoint) {
  if (breakpoint === 'desktop') {
    return Object.fromEntries(
      panels.map((panel) => [
        panel.uid,
        { x: panel.x, y: panel.y, w: panel.w, h: panel.h },
      ]),
    )
  }
  // Tablets pair up narrow panels; phones give every panel the full width
  const width = (panel) =>
    breakpoint === 'tablet' && panel.w <= 4 ? GRID_COLUMNS / 2 : GRID_COLUMNS
  const ordered = [...panels]
    .sort((a, b) => a.y - b.y || a.x - b.x)
    .map((panel) => ({
      uid: panel.uid,
      x: 0,
      y: 0,
      w: width(panel),
      h: panel.h,
    }))
  return Object.fromEntries(
    packInOrder(ordered).map(({ uid, ...rect }) => [uid, rect]),
  )
}
