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

import { FormatValueBase } from '@openc3/vue-common/widgets'

// The same formatting TlmViewer widgets use (format strings, BigInt, binary
// strings, arrays), callable without mixing it into a component
const formatter = FormatValueBase.methods

// Display text for a polled value. Panels poll CONVERTED values and apply the
// item's format string here, so units stay in their own column.
export function formatTelemetry(value, formatString = null) {
  if (value === undefined || value === null) return '--'
  // NaN and Infinity arrive as { raw: 'NaN' }
  if (value.raw !== undefined && value.json_class !== 'String') {
    return String(value.raw)
  }
  return formatter.formatValueBase.call(formatter, value, formatString)
}

// Packet times to the second: "2026/10/06 21:07:15.123" -> "2026/10/06 21:07:15"
export function toSeconds(time) {
  return typeof time === 'string'
    ? time.replace(/(\d{2}:\d{2}:\d{2})\.\d+/, '$1')
    : time
}

// hh:mm:ss UTC for a time in milliseconds
export function utcClock(ms = Date.now()) {
  return new Date(ms).toISOString().substring(11, 19) + ' UTC'
}
