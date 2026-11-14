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
import {
  MAX_H,
  bottomRow,
  breakpointFor,
  clampRect,
  deriveLayout,
  firstFit,
  resolveLayout,
  nudgeLayout,
} from '../layout'

const panel = (uid, x, y, w, h, type = 'VALUES') => ({ uid, type, x, y, w, h })

describe('clampRect', () => {
  it('keeps panels on the grid', () => {
    expect(clampRect({ x: 11, y: -2, w: 4, h: 40 })).toEqual({
      x: 8,
      y: 0,
      w: 4,
      h: MAX_H,
    })
  })

  it('honors the grid width', () => {
    expect(clampRect({ x: 20, y: 0, w: 6, h: 4 }, 24).x).toBe(18)
  })

  it('rounds fractional positions from dragging', () => {
    expect(clampRect({ x: 1.4, y: 2.6, w: 3.5, h: 4.2 })).toEqual({
      x: 1,
      y: 3,
      w: 4,
      h: 4,
    })
  })
})

describe('resolveLayout', () => {
  it('pushes overlapping panels down and floats everything up', () => {
    const layout = resolveLayout(
      [panel(1, 0, 0, 6, 4), panel(2, 0, 2, 6, 4), panel(3, 6, 10, 6, 4)],
      1,
    )
    expect(layout[1]).toEqual({ x: 0, y: 0, w: 6, h: 4 })
    expect(layout[2]).toEqual({ x: 0, y: 4, w: 6, h: 4 })
    // Nothing above it, so it floats to the top
    expect(layout[3]).toEqual({ x: 6, y: 0, w: 6, h: 4 })
  })

  it('swaps a panel dropped onto another into the vacated spot', () => {
    const layout = resolveLayout(
      [panel(1, 6, 0, 6, 4), panel(2, 6, 0, 6, 4)],
      1,
      { x: 0, y: 0 },
    )
    expect(layout[1]).toEqual({ x: 6, y: 0, w: 6, h: 4 })
    expect(layout[2]).toEqual({ x: 0, y: 0, w: 6, h: 4 })
  })
})

describe('firstFit and bottomRow', () => {
  const panels = [panel(1, 0, 0, 6, 4), panel(2, 6, 0, 3, 4)]

  it('finds the first free spot', () => {
    expect(firstFit(panels, 'VALUES', 3, 4)).toEqual({ x: 9, y: 0, w: 3, h: 4 })
  })

  it('goes below everything when nothing fits', () => {
    expect(firstFit(panels, 'VALUES', 12, 4)).toEqual({
      x: 0,
      y: 4,
      w: 12,
      h: 4,
    })
    expect(bottomRow(panels)).toBe(4)
  })
})

describe('breakpoints', () => {
  it('maps widths to breakpoints', () => {
    expect(breakpointFor(400)).toBe('phone')
    expect(breakpointFor(5000)).toBe('desktop')
  })

  it('keeps the desktop layout as written', () => {
    const panels = [panel(1, 3, 2, 4, 5)]
    expect(deriveLayout(panels, 'desktop')).toEqual({
      1: { x: 3, y: 2, w: 4, h: 5 },
    })
  })

  it('gives every panel the full width on phones, in reading order', () => {
    const layout = deriveLayout(
      [panel(1, 0, 0, 6, 4), panel(2, 6, 0, 6, 2), panel(3, 6, 2, 6, 2)],
      'phone',
    )
    expect(Object.values(layout).every((rect) => rect.w === 12)).toBe(true)
    expect(layout[1].y).toBeLessThan(layout[2].y)
    expect(layout[2].y).toBeLessThan(layout[3].y)
  })

  it('pairs narrow panels on tablets', () => {
    const layout = deriveLayout(
      [panel(1, 0, 0, 3, 4), panel(2, 3, 0, 3, 4), panel(3, 6, 0, 6, 4)],
      'tablet',
    )
    expect(layout[1]).toEqual({ x: 0, y: 0, w: 6, h: 4 })
    expect(layout[2]).toEqual({ x: 6, y: 0, w: 6, h: 4 })
    expect(layout[3].w).toBe(12)
  })
})

describe('nudgeLayout', () => {
  const panel = (uid, x, y, w, h) => ({ uid, type: 'VALUES', x, y, w, h })
  // A over B in the left half, C alone on the right
  const panels = [
    panel(1, 0, 0, 6, 3),
    panel(2, 0, 3, 6, 4),
    panel(3, 6, 0, 6, 5),
  ]

  it('moves down past the panel below, swapping them', () => {
    const layout = nudgeLayout(panels, 1, { dy: 1 })
    expect(layout[2]).toMatchObject({ x: 0, y: 0 })
    expect(layout[1]).toMatchObject({ x: 0, y: 4 })
  })

  it('moves back up the same way', () => {
    const down = nudgeLayout(panels, 1, { dy: 1 })
    const moved = panels.map((p) => ({ ...p, ...down[p.uid] }))
    const up = nudgeLayout(moved, 1, { dy: -1 })
    expect(up[1]).toMatchObject({ y: 0 })
    expect(up[2]).toMatchObject({ y: 3 })
  })

  it("doesn't move down with nothing below", () => {
    expect(nudgeLayout(panels, 2, { dy: 1 })).toBeNull()
    expect(nudgeLayout(panels, 3, { dy: 1 })).toBeNull()
  })

  it('still moves sideways and resizes', () => {
    expect(nudgeLayout(panels, 3, { dx: -1 })[3]).toMatchObject({ x: 5 })
    expect(nudgeLayout(panels, 1, { dh: 1 })[1]).toMatchObject({ h: 4 })
    expect(nudgeLayout(panels, 1, { dh: 1 })[2]).toMatchObject({ y: 4 })
  })
})

describe('arrow key runs', () => {
  const panel = (uid, x, y, w, h) => ({ uid, type: 'VALUES', x, y, w, h })
  // Found by a random search: B and C stacked in one column
  const panels = [
    panel(1, 6, 0, 2, 2),
    panel(2, 6, 2, 2, 3),
    panel(3, 6, 5, 2, 3),
    panel(4, 4, 0, 2, 3),
    panel(5, 2, 0, 2, 4),
  ]
  const positions = (layout) =>
    Object.fromEntries(
      Object.entries(layout).map(([uid, { x, y }]) => [uid, [x, y]]),
    )
  const start = positions(Object.fromEntries(panels.map((p) => [p.uid, p])))

  it('one press at a time, there and back reorders panels', () => {
    let current = panels
    for (const dx of [-1, -1, -1, 1, 1, 1]) {
      const layout = nudgeLayout(current, 3, { dx })
      current = current.map((p) => ({ ...p, ...layout[p.uid] }))
    }
    const end = positions(Object.fromEntries(current.map((p) => [p.uid, p])))
    expect(end).not.toEqual(start)
  })

  it('as a run from where it started, there and back restores them', () => {
    // The total after three lefts and three rights
    expect(positions(nudgeLayout(panels, 3, { dx: -3 }))).not.toEqual(start)
    expect(positions(nudgeLayout(panels, 3, { dx: 0 }))).toEqual(start)
  })
})
