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

export default {
  methods: {
    isFloat(str) {
      // Regex to identify a string as a floating point number
      if (/^\s*[-+]?\d*\.\d+\s*$/.test(str)) {
        return true
      }
      // Regex to identify a string as a floating point number in scientific notation.
      if (/^\s*[-+]?(\d+((\.\d+)?)|(\.\d+))[eE][-+]?\d+\s*$/.test(str)) {
        return true
      }
      return false
    },

    isInt(str) {
      // Regular expression to identify a String as an integer
      if (/^\s*[-+]?\d+\s*$/.test(str)) {
        return true
      }

      // # Regular expression to identify a String as an integer in hexadecimal format
      if (/^\s*0[xX][\dabcdefABCDEF]+\s*$/.test(str)) {
        return true
      }
      return false
    },

    isArray(str) {
      // Regular expression to identify a String as an Array
      return /^\s*\[.*\]\s*$/.test(str)
    },

    removeQuotes(str) {
      // Return the string with leading and trailing quotes removed
      if (str.length < 2) {
        return str
      }
      let firstChar = str.charAt(0)
      if (firstChar !== '"' && firstChar !== "'") {
        return str
      }
      let lastChar = str.charAt(str.length - 1)
      if (firstChar !== lastChar) {
        return str
      }
      return str.slice(1, -1)
    },

    convertToValue(param) {
      if (param.val !== undefined && param.states && !this.cmdRaw) {
        const stateName = Object.keys(param.states).find(
          (state) => param.states[state].value === param.val,
        )
        if (stateName !== undefined) {
          return stateName
        }
        // No matching state found (manually entered value), fall through
        // to parse the raw value below
      }
      if (typeof param.val !== 'string') {
        return param.val
      }

      let str = param.val
      let quotesRemoved = this.removeQuotes(str)
      if (str === quotesRemoved) {
        let upcaseStr = str.toUpperCase()
        if (
          (param.type === 'STRING' || param.type === 'BLOCK') &&
          upcaseStr.startsWith('0X')
        ) {
          let hexStr = upcaseStr.slice(2)
          if (hexStr.length % 2 !== 0) {
            hexStr = '0' + hexStr
          }
          let jstr = { json_class: 'String', raw: [] }
          for (let i = 0; i < hexStr.length; i += 2) {
            let nibble = hexStr.charAt(i) + hexStr.charAt(i + 1)
            jstr.raw.push(Number.parseInt(nibble, 16))
          }
          return jstr
        }
        if (upcaseStr === 'INFINITY') return Number.POSITIVE_INFINITY
        if (upcaseStr === '-INFINITY') return Number.NEGATIVE_INFINITY
        if (upcaseStr === 'NAN') return Number.NaN
        if (this.isFloat(str)) return Number.parseFloat(str)
        if (this.isInt(str)) {
          if (!Number.isSafeInteger(Number(str))) return BigInt(str)
          return Number.parseInt(str)
        }
        if (this.isArray(str)) {
          try {
            return JSON.parse(str)
          } catch {
            throw new Error(`Invalid array parameter value: ${str}`)
          }
        }
        return str
      }
      return quotesRemoved
    },

    convertToString(value) {
      let returnValue = ''
      if (Object.prototype.toString.call(value).slice(8, -1) === 'Array') {
        let arrayLength = value.length
        returnValue = '[ '
        for (let i = 0; i < arrayLength; i++) {
          if (
            Object.prototype.toString.call(value[i]).slice(8, -1) === 'String'
          ) {
            returnValue += '"' + value[i] + '"'
          } else {
            returnValue += value[i]
          }
          if (i !== arrayLength - 1) {
            returnValue += ', '
          }
        }
        returnValue += ' ]'
      } else if (
        Object.prototype.toString.call(value).slice(8, -1) === 'Object'
      ) {
        if (value.json_class === 'String' && value.raw) {
          // This is binary data, display in hex.
          returnValue = '0x'
          for (let part of value.raw) {
            returnValue += part.toString(16).padStart(2, '0').toUpperCase()
          }
        } else if (value.json_class === 'Float' && value.raw) {
          returnValue = value.raw
        } else {
          // For other objects, use JSON.stringify as a fallback
          returnValue = JSON.stringify(value).replace(/\\n/g, '')
        }
      } else {
        returnValue = String(value)
      }
      return returnValue
    },
  },
}
