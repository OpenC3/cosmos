/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import 'sprintf-js'
export default {
  methods: {
    formatValueBase(value, formatString) {
      if (this.isJsonString(value)) {
        return this.formatJsonString(value)
      }
      if (Array.isArray(value)) {
        return JSON.stringify(value).replace(/\\n/g, '')
      }
      if (this.isObject(value)) {
        return JSON.stringify(value).replace(/\\n/g, '')
      }
      if (formatString && value) {
        if (typeof value === 'bigint') {
          return this.formatBigInt(value, formatString)
        }
        return sprintf(formatString, value)
      }
      if (value === null || value === undefined) {
        return 'null'
      }
      return String(value)
    },
    // sprintf-js doesn't support BigInt values so we handle common
    // integer format specifiers manually to preserve full precision
    formatBigInt(value, formatString) {
      const match = formatString.match(
        /^([^%]*)%([#0 +-]*)(\d+)?\.?(\d+)?([diouxX])(.*)$/,
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
          const width = parseInt(widthStr)
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
    },
    isJsonString(value) {
      return (
        value && value['json_class'] === 'String' && value['raw'] !== undefined
      )
    },
    formatJsonString(value) {
      let result = Array.from(value['raw'].slice(0, 32), (byte) =>
        ('0' + (byte & 0xff).toString(16)).slice(-2),
      )
        .join(' ')
        .toUpperCase()
      if (value['raw'].length > 32) {
        result += '...'
      }
      return result
    },
    formatArray(value) {
      return (
        '[' +
        value
          .map((item) => (typeof item === 'string' ? `"${item}"` : item))
          .join(', ') +
        ']'
      )
    },
    isObject(value) {
      return Object.prototype.toString.call(value).slice(8, -1) === 'Object'
    },
  },
}
