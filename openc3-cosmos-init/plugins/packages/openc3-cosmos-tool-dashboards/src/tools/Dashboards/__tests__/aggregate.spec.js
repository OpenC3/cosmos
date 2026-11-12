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
import { aggregate, limitsLevel } from '../panels/aggregate'

describe('aggregate', () => {
  // Gaps (null) and non numbers are skipped
  const stats = aggregate([4, null, 2, 'x', NaN, 8, 6])

  it('computes the statistics', () => {
    expect(stats).toMatchObject({
      MIN: 2,
      MAX: 8,
      AVG: 5,
      MEDIAN: 5,
      RANGE: 6,
      FIRST: 4,
      LAST: 6,
      SUM: 20,
      COUNT: 4,
    })
    expect(stats.STDDEV).toBeCloseTo(Math.sqrt(5))
    // Interpolated like numpy: 2,4,6,8 at rank 2.85
    expect(stats.PERCENTILE).toBeCloseTo(7.7)
  })

  it('takes a percentile', () => {
    expect(aggregate([5, 1, 4, 2, 3], { percentile: 50 }).PERCENTILE).toBe(3)
  })

  it('only sorts when median or percentile is asked for', () => {
    const quick = aggregate([3, 1, 2], { stats: ['MIN', 'MAX'] })
    expect(quick).toMatchObject({ MIN: 1, MAX: 3, MEDIAN: null })
    expect(aggregate([3, 1, 2], { stats: ['MEDIAN'] }).MEDIAN).toBe(2)
  })

  it('keeps precision with large offsets', () => {
    const big = aggregate([1e9 + 4, 1e9 + 2, 1e9 + 8, 1e9 + 6])
    expect(big.STDDEV).toBeCloseTo(Math.sqrt(5))
  })

  it('is empty without samples', () => {
    const empty = aggregate([null, null])
    expect(empty.COUNT).toBe(0)
    expect(empty.MIN).toBeNull()
    expect(empty.AVG).toBeNull()
  })
})

describe('limitsLevel', () => {
  const limits = { red_low: 0, yellow_low: 10, yellow_high: 90, red_high: 100 }
  it.each([
    [-1, 'critical'],
    [5, 'caution'],
    [50, 'normal'],
    [95, 'caution'],
    [101, 'critical'],
  ])('%s is %s', (value, level) => {
    expect(limitsLevel(value, limits)).toBe(level)
  })
  it('is null without limits or a value', () => {
    expect(limitsLevel(5, null)).toBeNull()
    expect(limitsLevel(null, limits)).toBeNull()
  })
})
