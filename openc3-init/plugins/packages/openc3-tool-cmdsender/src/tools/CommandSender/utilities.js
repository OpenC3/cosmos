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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
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
      if (/^\s*\[.*\]\s*$/.test(str)) {
        return true
      }
      return false
    },

    removeQuotes(str) {
      // Return the string with leading and trailing quotes removed
      if (str.length < 2) {
        return str
      }
      var firstChar = str.charAt(0)
      if (firstChar !== '"' && firstChar !== "'") {
        return str
      }
      var lastChar = str.charAt(str.length - 1)
      if (firstChar !== lastChar) {
        return str
      }
      return str.slice(1, -1)
    },

    convertToString(value) {
      var i = 0
      var returnValue = ''
      if (Object.prototype.toString.call(value).slice(8, -1) === 'Array') {
        var arrayLength = value.length
        returnValue = '[ '
        for (i = 0; i < arrayLength; i++) {
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
          for (i = 0; i < value.raw.length; i++) {
            var nibble = value.raw[i].toString(16).toUpperCase()
            if (nibble.length < 2) {
              nibble = '0' + nibble
            }
            returnValue += nibble
          }
        } else if (value.json_class === 'Float' && value.raw) {
          returnValue = value.raw
        }
      } else {
        returnValue = String(value)
      }
      return returnValue
    },
  },
}
