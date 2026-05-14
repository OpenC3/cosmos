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
// Match any whitespace control character we want to make visible in
// single-line displays. Kept as a module-level constant so the regex is
// compiled once and reused across every formatValueBase call.
const WHITESPACE_CONTROL_REGEX = /[\n\r\t]/
const WHITESPACE_CONTROL_REGEX_G = /[\n\r\t]/g
export default {
  methods: {
    formatValueBase(value, formatString, options) {
      if (this.isJsonString(value)) {
        return this.formatJsonString(value)
      }
      const preserveWhitespace = options?.preserveWhitespace === true
      if (Array.isArray(value)) {
        return this.escapeWhitespace(JSON.stringify(value), preserveWhitespace)
      }
      if (this.isObject(value)) {
        return this.escapeWhitespace(JSON.stringify(value), preserveWhitespace)
      }
      if (formatString && value) {
        if (typeof value === 'bigint') {
          return this.formatBigInt(value, formatString)
        }
        return this.escapeWhitespace(
          sprintf(formatString, value),
          preserveWhitespace,
        )
      }
      if (value === null || value === undefined) {
        return 'null'
      }
      if (typeof value === 'string') {
        return this.escapeWhitespace(value, preserveWhitespace)
      }
      return String(value)
    },
    // Make embedded newlines, carriage returns, and tabs visible in
    // single-line displays (e.g. Packet Viewer) by replacing them with their
    // escape sequences. Pass preserveWhitespace=true to return the value
    // unchanged for multi-line displays such as the TEXTBOX widget.
    escapeWhitespace(value, preserveWhitespace) {
      if (preserveWhitespace || typeof value !== 'string') {
        return value
      }
      // Cheap test first so we only allocate a new string when needed.
      if (!WHITESPACE_CONTROL_REGEX.test(value)) {
        return value
      }
      return value.replace(WHITESPACE_CONTROL_REGEX_G, (m) => {
        if (m === '\n') return String.raw`\n`
        if (m === '\r') return String.raw`\r`
        return String.raw`\t`
      })
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
