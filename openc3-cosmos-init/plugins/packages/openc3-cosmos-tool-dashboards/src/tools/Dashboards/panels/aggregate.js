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

// Statistics over an item's history in the dashboard's time range, for
// AGGREGATE panels. `limits`: a reading of the item, so it's checked
// against the item's limits. `unitless`: shown without the item's units.

export const STATISTICS = [
  { value: 'MIN', title: 'Min', limits: true },
  { value: 'MAX', title: 'Max', limits: true },
  { value: 'AVG', title: 'Average', limits: true },
  { value: 'MEDIAN', title: 'Median', limits: true },
  { value: 'PERCENTILE', title: 'Percentile', limits: true },
  { value: 'STDDEV', title: 'Std dev' },
  { value: 'RANGE', title: 'Range' },
  { value: 'FIRST', title: 'First', limits: true },
  { value: 'LAST', title: 'Last', limits: true },
  { value: 'SUM', title: 'Sum' },
  { value: 'COUNT', title: 'Count', unitless: true },
]

export const DEFAULT_STATISTICS = ['MIN', 'MAX', 'AVG']

// Statistics that need the samples sorted, the only costly part
const ORDERED = ['MEDIAN', 'PERCENTILE']

// Linear interpolation between the closest ranks, like numpy's default
function percentileOf(sorted, percent) {
  if (!sorted.length) return null
  const rank = (Math.min(Math.max(percent, 0), 100) / 100) * (sorted.length - 1)
  const low = Math.floor(rank)
  const high = Math.ceil(rank)
  return sorted[low] + (sorted[high] - sorted[low]) * (rank - low)
}

// Statistics of one item's values in the time range, oldest first, as
// { NAME: number | null }; null where there's nothing to compute from.
// Values that aren't finite numbers (gaps, strings) are skipped. One pass,
// plus a sort only when `stats` asks for MEDIAN or PERCENTILE (all when
// `stats` is left out), so it keeps up with long ranges of fast items.
export function aggregate(values, { percentile = 95, stats = null } = {}) {
  const ordered = !stats || ORDERED.some((name) => stats.includes(name))
  const numbers = ordered ? new Float64Array(values.length) : null
  let count = 0
  let sum = 0
  let min = Infinity
  let max = -Infinity
  let first = null
  let last = null
  // Welford's running mean and squared deviations: one pass, and steady
  // with large values
  let mean = 0
  let squares = 0
  for (const value of values) {
    if (typeof value !== 'number' || !Number.isFinite(value)) continue
    if (numbers) numbers[count] = value
    count++
    sum += value
    if (value < min) min = value
    if (value > max) max = value
    if (first === null) first = value
    last = value
    const delta = value - mean
    mean += delta / count
    squares += delta * (value - mean)
  }
  if (!count) {
    return Object.fromEntries(
      STATISTICS.map(({ value }) => [value, value === 'COUNT' ? 0 : null]),
    )
  }
  // Typed arrays sort numerically, much faster than a comparator
  const sorted = numbers ? numbers.subarray(0, count).sort() : null
  return {
    MIN: min,
    MAX: max,
    AVG: sum / count,
    MEDIAN: sorted ? percentileOf(sorted, 50) : null,
    PERCENTILE: sorted ? percentileOf(sorted, percentile) : null,
    // Population standard deviation: of every sample in the range
    STDDEV: Math.sqrt(squares / count),
    RANGE: max - min,
    FIRST: first,
    LAST: last,
    SUM: sum,
    COUNT: count,
  }
}

// The status a statistic in the item's units would have against its limits
// ({ red_low, yellow_low, yellow_high, red_high }), or null without limits
export function limitsLevel(value, limits) {
  if (!limits || typeof value !== 'number') return null
  if (value < limits.red_low || value > limits.red_high) return 'critical'
  if (value < limits.yellow_low || value > limits.yellow_high) return 'caution'
  return 'normal'
}
