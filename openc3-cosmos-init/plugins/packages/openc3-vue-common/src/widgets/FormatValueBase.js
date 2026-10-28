/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import 'sprintf-js'

// Value formatting shared by the widgets (FormatValueBase mixin) and callable
// directly, e.g. from Composition API code

export function isJsonString(value) {
  return value && value['json_class'] === 'String' && value['raw'] !== undefined
}

export function formatJsonString(value) {
  let result = Array.from(value['raw'].slice(0, 32), (byte) =>
    ('0' + (byte & 0xff).toString(16)).slice(-2),
  )
    .join(' ')
    .toUpperCase()
  if (value['raw'].length > 32) {
    result += '...'
  }
  return result
}

export function formatArray(value) {
  return (
    '[' +
    value
      .map((item) => (typeof item === 'string' ? `"${item}"` : item))
      .join(', ') +
    ']'
  )
}

export function isObject(value) {
  return Object.prototype.toString.call(value).slice(8, -1) === 'Object'
}

// sprintf-js doesn't support BigInt values so we handle common
// integer format specifiers manually to preserve full precision
export function formatBigInt(value, formatString) {
  const match = formatString.match(
    // Width can't start with 0 (that's the zero-pad flag) and the precision
    // digits only exist with the '.', so neither can overlap the group before it
    /^([^%]*)%([#0 +-]*)([1-9]\d*)?(?:\.(\d*))?([diouxX])(.*)$/,
  )
  if (match) {
    const [, prefix, flags, widthStr, , specifier, suffix] = match
    let isNeg = value < 0n
    let absVal = isNeg ? -value : value
    let str
    switch (specifier) {
      case 'd':
      case 'i':
      case 'u':
        str = absVal.toString(10)
        break
      case 'o':
        str = absVal.toString(8)
        break
      case 'x':
        str = absVal.toString(16)
        break
      case 'X':
        str = absVal.toString(16).toUpperCase()
        break
    }
    if (flags.includes('#')) {
      if (specifier === 'x') str = '0x' + str
      else if (specifier === 'X') str = '0X' + str
      else if (specifier === 'o' && !str.startsWith('0')) str = '0' + str
    }
    if (isNeg && (specifier === 'd' || specifier === 'i')) {
      str = '-' + str
    }
    if (widthStr) {
      const width = Number.parseInt(widthStr)
      if (flags.includes('-')) {
        str = str.padEnd(width, ' ')
      } else {
        str = str.padStart(width, flags.includes('0') ? '0' : ' ')
      }
    }
    return prefix + str + suffix
  }
  // Unsupported format specifier, return as string
  return value.toString()
}

export function formatValueBase(value, formatString) {
  if (isJsonString(value)) {
    return formatJsonString(value)
  }
  if (Array.isArray(value)) {
    return JSON.stringify(value).replace(/\\n/g, '')
  }
  if (isObject(value)) {
    return JSON.stringify(value).replace(/\\n/g, '')
  }
  if (formatString && value) {
    if (typeof value === 'bigint') {
      return formatBigInt(value, formatString)
    }
    return sprintf(formatString, value)
  }
  if (value === null || value === undefined) {
    return 'null'
  }
  return String(value)
}

// The Options API mixin for widgets
export default {
  methods: {
    formatValueBase,
    formatBigInt,
    isJsonString,
    formatJsonString,
    formatArray,
    isObject,
  },
}
