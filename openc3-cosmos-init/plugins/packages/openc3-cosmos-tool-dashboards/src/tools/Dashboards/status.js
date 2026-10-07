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

// Status levels from the Dashboards style system. Each level has its own
// symbol shape so status never depends on color alone.
export const SYMBOL_PATHS = {
  critical: 'M6 0.8L11.6 10.8H0.4Z',
  serious: 'M1.5 1.5H10.5V10.5H1.5Z',
  caution: 'M6 0.4L11.6 6L6 11.6L0.4 6Z',
  normal: 'M1 6A5 5 0 1 0 11 6A5 5 0 1 0 1 6Z',
  standby:
    'M1 6A5 5 0 1 0 11 6A5 5 0 1 0 1 6ZM3.4 6A2.6 2.6 0 1 0 8.6 6A2.6 2.6 0 1 0 3.4 6Z',
  off: 'M1 4.75H11V7.25H1Z',
}

export const LEVEL_LABELS = {
  critical: 'Critical',
  serious: 'Serious',
  caution: 'Caution',
  normal: 'Normal',
  standby: 'Standby',
  off: 'Off',
}

// Most severe first
const SEVERITY = ['critical', 'serious', 'caution', 'off', 'standby', 'normal']

// Map a COSMOS limits state (as returned by get_tlm_values or a limits event)
// to a style system level. Returns null for items without limits.
export function stateToLevel(state) {
  if (!state) return null
  if (state.startsWith('RED')) return 'critical'
  if (state.startsWith('YELLOW')) return 'caution'
  if (state.startsWith('GREEN')) return 'normal'
  if (state === 'BLUE') return 'standby'
  if (state === 'STALE') return 'off'
  return null
}

export function worstLevel(levels) {
  let worst = null
  for (const level of levels) {
    if (!level) continue
    if (worst === null || SEVERITY.indexOf(level) < SEVERITY.indexOf(worst)) {
      worst = level
    }
  }
  return worst
}

// Panel border treatment for the worst status shown in a panel
export function ringClass(level) {
  if (level === 'critical') return 'ring-critical'
  if (level === 'caution') return 'ring-caution'
  return ''
}

// Human readable reason an item is out of limits, e.g. "above RED HIGH 55"
export function limitsReason(state, limits) {
  if (!state) return ''
  const value = (key) =>
    limits && limits[key] !== undefined ? ` ${limits[key]}` : ''
  switch (state) {
    case 'RED_HIGH':
      return `above RED HIGH${value('red_high')}`
    case 'RED_LOW':
      return `below RED LOW${value('red_low')}`
    case 'YELLOW_HIGH':
      return `above YELLOW HIGH${value('yellow_high')}`
    case 'YELLOW_LOW':
      return `below YELLOW LOW${value('yellow_low')}`
    default:
      return state.replace(/_/g, ' ')
  }
}
