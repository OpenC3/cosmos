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

// The time range every graph and sparkline on a dashboard shows, picked
// from the header like Grafana's time picker. Always "the last N seconds"
// (before the playback time during playback). Remembered in this browser.

import { readString, writeString } from './storage'

const STORAGE_KEY = 'dashboards__time_range'

export const DEFAULT_TIME_RANGE = 120
export const TIME_RANGE_PRESETS = [120, 300, 900, 1800]
export const MIN_TIME_RANGE = 30
export const MAX_TIME_RANGE = 24 * 3600

export const TIME_RANGE_UNITS = [
  { title: 'seconds', value: 1 },
  { title: 'minutes', value: 60 },
  { title: 'hours', value: 3600 },
]

// Largest unit that divides the range evenly: [amount, unit seconds]
export function splitTimeRange(seconds) {
  const unit = [3600, 60, 1].find((size) => seconds % size === 0)
  return [seconds / unit, unit]
}

// "Last 5 minutes", or "5m" when short
export function timeRangeLabel(seconds, short = false) {
  const [amount, unit] = splitTimeRange(seconds)
  const name = { 1: 'second', 60: 'minute', 3600: 'hour' }[unit]
  if (short) return `${amount}${name[0]}`
  return `Last ${amount} ${name}${amount === 1 ? '' : 's'}`
}

// Message when a custom range is out of bounds, else null
export function timeRangeProblem(seconds) {
  if (!Number.isFinite(seconds) || seconds < MIN_TIME_RANGE) {
    return `At least ${MIN_TIME_RANGE} seconds`
  }
  if (seconds > MAX_TIME_RANGE) return 'At most 24 hours'
  return null
}

export function loadTimeRange() {
  const seconds = Number(readString(STORAGE_KEY))
  return seconds && !timeRangeProblem(seconds) ? seconds : DEFAULT_TIME_RANGE
}

// The default isn't stored, so changing the default moves everyone on it
export function saveTimeRange(seconds) {
  writeString(STORAGE_KEY, seconds === DEFAULT_TIME_RANGE ? null : seconds)
}
