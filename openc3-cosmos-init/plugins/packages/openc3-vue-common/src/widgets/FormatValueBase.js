/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
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
        return sprintf(formatString, value)
      }
      if (value === null || value === undefined) {
        return 'null'
      }
      return String(value)
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
