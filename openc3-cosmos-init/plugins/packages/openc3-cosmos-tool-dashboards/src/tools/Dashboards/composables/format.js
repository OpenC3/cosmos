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

// The same formatting TlmViewer widgets use (format strings, BigInt, binary
// strings, arrays) and the same time zone conversion
import { formatValueBase } from '@openc3/vue-common/widgets'
import { formatUtcToLocal } from '@openc3/vue-common/util'

// Display text for a polled value. Panels poll CONVERTED values and apply the
// item's format string here, so units stay in their own column.
export function formatTelemetry(value, formatString = null) {
  if (value === undefined || value === null) return '--'
  // NaN and Infinity arrive as { raw: 'NaN' }
  if (value.raw !== undefined && value.json_class !== 'String') {
    return String(value.raw)
  }
  return formatValueBase(value, formatString)
}

// Short text for a number in a small panel: 2 decimal places, and k / M / B
// for thousands, millions and billions (1234567 -> "1.23M"). Whole numbers
// under 1000 stay whole.
const COMPACT_UNITS = [
  [1, ''],
  [1e3, 'k'],
  [1e6, 'M'],
  [1e9, 'B'],
]
export function compactNumber(value) {
  if (!Number.isFinite(value)) return String(value)
  const size = Math.abs(value)
  let index = Math.max(
    0,
    COMPACT_UNITS.findLastIndex(([unit]) => size >= unit),
  )
  // Move up a unit when rounding reaches 1000: 999.999 is "1.00k"
  while (
    index < COMPACT_UNITS.length - 1 &&
    Math.round((size / COMPACT_UNITS[index][0]) * 100) >= 100000
  ) {
    index++
  }
  const [unit, suffix] = COMPACT_UNITS[index]
  if (!suffix && Number.isInteger(value)) return String(value)
  // A tiny negative rounds to "-0.00"; it's just 0
  const text = (value / unit).toFixed(2).replace(/^-(0\.00)$/, '$1')
  return `${text}${suffix}`
}

// Times to the second: "2026-10-06 15:07:15.123" -> "2026-10-06 15:07:15"
export function toSeconds(time) {
  return typeof time === 'string'
    ? time.replace(/(\d{2}:\d{2}:\d{2})\.\d+/, '$1')
    : time
}

// Times show in the time zone set in Admin > Settings, 'local' or 'UTC'

// hh:mm:ss for a time in milliseconds, with " UTC" when in UTC
export function clock(ms = Date.now(), timeZone = 'local') {
  const utc = timeZone === 'UTC'
  const time = new Date(ms).toLocaleTimeString(
    'en-GB',
    utc ? { timeZone: 'UTC' } : {},
  )
  return utc ? `${time} UTC` : time
}

// A COSMOS time ("2026/10/06 21:07:15.123", always UTC) in the time zone, the
// way Telemetry Viewer shows it ("2026-10-06 15:07:15.123"). Anything else is
// returned as is.
export function formatTime(time, timeZone = 'local') {
  if (!/^\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}:\d{2}/.test(time)) return time
  return formatUtcToLocal(new Date(time.replaceAll('/', '-')), timeZone)
}

// Display text for an item's value: formatTelemetry, with the packet time
// items in the time zone
export function formatItem(itemName, value, formatString, timeZone) {
  if (/^(PACKET|RECEIVED)_TIMEFORMATTED$/.test(itemName)) {
    value = formatTime(value, timeZone)
  }
  return formatTelemetry(value, formatString)
}
