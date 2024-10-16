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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

export default {
  methods: {
    formatValueBase(value, formatString) {
      // Convert json raw strings into the raw bytes
      // Only convert the first 32 bytes before adding an ellipse
      // TODO: Handle units on a BLOCK item
      // TODO: Render data in a BLOCK item as bytes (instead of ASCII)
      if (
        value &&
        value['json_class'] === 'String' &&
        value['raw'] !== undefined
      ) {
        let result = Array.from(value['raw'].slice(0, 32), function (byte) {
          return ('0' + (byte & 0xff).toString(16)).slice(-2)
        })
          .join(' ')
          .toUpperCase()
        if (value['raw'].length > 32) {
          result += '...'
        }
        return result
      }
      if (Object.prototype.toString.call(value).slice(8, -1) === 'Array') {
        let result = '['
        for (let i = 0; i < value.length; i++) {
          if (
            Object.prototype.toString.call(value[i]).slice(8, -1) === 'String'
          ) {
            result += '"' + value[i] + '"'
          } else {
            result += value[i]
          }
          if (i != value.length - 1) {
            result += ', '
          }
        }
        result += ']'
        return result
      }
      if (Object.prototype.toString.call(value).slice(8, -1) === 'Object') {
        return ''
      }
      if (formatString && value) {
        return sprintf(formatString, value)
      }
      return '' + value
    },
  },
}
