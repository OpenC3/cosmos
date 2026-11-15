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

// Item limits in the shape get_item returns ({ red_low, yellow_low,
// yellow_high, red_high } plus green_low/green_high for operational limits),
// as the limits bar, gauge, graph and sparkline draw them.

function hasLimits(l) {
  return !!l && l.red_low !== undefined && l.red_high !== undefined
}

// The red limits plus 10% of their range on each side, like the COSMOS
// LimitsBar widget. Null without limits.
export function paddedScale(l) {
  if (!hasLimits(l)) return null
  const pad = Math.max((l.red_high - l.red_low) * 0.1, Number.EPSILON)
  return { min: l.red_low - pad, max: l.red_high + pad }
}

// Colored zones from min to max, in value units. Operational limits add the
// inner green_low..green_high range as a standby (blue) zone on top.
export function limitZones(l, min, max) {
  if (!hasLimits(l)) return []
  const zones = [
    ['critical', min, l.red_low],
    ['caution', l.red_low, l.yellow_low],
    ['normal', l.yellow_low, l.yellow_high],
    ['caution', l.yellow_high, l.red_high],
    ['critical', l.red_high, max],
  ]
  if (l.green_low !== undefined && l.green_high !== undefined) {
    zones.push(['standby', l.green_low, l.green_high])
  }
  return zones.map(([level, from, to]) => ({ level, from, to }))
}

// The yellow and red limits as threshold lines, highest first
export function limitLines(l) {
  if (!l) return []
  return [
    { key: 'rh', level: 'critical', name: 'RED HIGH', value: l.red_high },
    { key: 'yh', level: 'caution', name: 'YELLOW HIGH', value: l.yellow_high },
    { key: 'yl', level: 'caution', name: 'YELLOW LOW', value: l.yellow_low },
    { key: 'rl', level: 'critical', name: 'RED LOW', value: l.red_low },
  ]
}

// Status of a value checked against limits on the client, for values the
// server's limits state doesn't cover (past points, custom limits)
export function levelOf(value, l) {
  if (!l || typeof value !== 'number') return null
  if (value < l.red_low || value > l.red_high) return 'critical'
  if (value < l.yellow_low || value > l.yellow_high) return 'caution'
  return 'normal'
}
