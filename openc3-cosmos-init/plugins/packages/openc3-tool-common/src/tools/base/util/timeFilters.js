/*
# Copyright 2024 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { format, parseISO, subMinutes } from 'date-fns'
import { formatInTimeZone } from 'date-fns-tz'

const dateFormat = 'yyyy-MM-dd'
const timeFormat = 'HH:mm:ss.SSS'
const timeFormatHMS = 'HH:mm:ss'
const dateTimeFormat = `${dateFormat} ${timeFormat}`
export default {
  methods: {
    // Convert a UTC stamp into a local time
    formatUtcToLocal(date, timeZone) {
      // Default to local time if the timezone isn't set
      if (!timeZone || timeZone === 'local') {
        // subtrack off the timezone offset to get it back to local time
        return format(
          subMinutes(date, date.getTimezoneOffset()),
          dateTimeFormat
        )
      } else {
        return format(date, dateTimeFormat)
      }
    },
    formatDateTime(date, timeZone) {
      // Default to local time if the timezone isn't set
      if (!timeZone || timeZone === 'local') {
        return format(date, dateTimeFormat)
      } else {
        return formatInTimeZone(date, timeZone, dateTimeFormat)
      }
    },
    formatDate: function (date, timeZone) {
      // Default to local time if the timezone isn't set
      if (!timeZone || timeZone === 'local') {
        return format(date, dateFormat)
      } else {
        return formatInTimeZone(date, this.timeZone, dateFormat)
      }
    },
    formatTime: function (date, timeZone, formatString = timeFormat) {
      // Default to local time if the timezone isn't set
      if (!timeZone || timeZone === 'local') {
        return format(date, formatString)
      } else {
        return formatInTimeZone(date, this.timeZone, formatString)
      }
    },
    formatTimeHMS: function (date, timeZone) {
      return this.formatTime(date, timeZone, timeFormatHMS)
    },
    formatTimestamp(timestamp, timeZone) {
      return this.formatDateTime(parseISO(timestamp), timeZone)
    },
    formatSeconds(secs, timeZone) {
      return this.formatDateTime(new Date(secs * 1000), timeZone)
    },
    formatNanoseconds(nanoSecs, timeZone) {
      return this.formatDateTime(
        new Date(parseInt(nanoSecs) / 1_000_000),
        timeZone
      )
    },
  },
}
