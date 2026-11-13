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
import { hoverReach, nearestValue } from '../panels/tlmSeries'

// One value a second, with rows from other packets (null) in between
const times = [10, 10.5, 11, 11.5, 12, 12.5, 13]
const values = [1, null, 2, null, 3, null, null]

describe('nearestValue', () => {
  it('finds the nearest real value across gaps', () => {
    expect(nearestValue(times, values, 10.4, 5)).toBe(1)
    expect(nearestValue(times, values, 11.4, 5)).toBe(2)
    expect(nearestValue(times, values, 12.6, 5)).toBe(3)
  })

  it('prefers the closer side', () => {
    expect(nearestValue(times, values, 11.9, 5)).toBe(3)
  })

  it('gives the newest value past the end, however old', () => {
    expect(nearestValue(times, values, 500, 5)).toBe(3)
  })

  it('has nothing before the history starts', () => {
    expect(nearestValue(times, values, 5, 5)).toBeNull()
    expect(nearestValue([], [], 5, 5)).toBeNull()
    expect(nearestValue(times, values, null, 5)).toBeNull()
  })

  it('stops looking past the reach', () => {
    const sparse = [0, 1, 2, 3, 4, 100]
    const gappy = [5, null, null, null, null, 6]
    expect(nearestValue(sparse, gappy, 3.5, 2)).toBeNull()
    expect(nearestValue(sparse, gappy, 1.5, 2)).toBe(5)
  })
})

describe('hoverReach', () => {
  it('is at least 5 seconds, else a 40th of the range', () => {
    expect(hoverReach(60)).toBe(5)
    expect(hoverReach(3600)).toBe(90)
  })
})
