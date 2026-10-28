/*
# Copyright 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { format, parseISO, subMinutes } from 'date-fns'
import { formatInTimeZone } from 'date-fns-tz'

const dateFormat = 'yyyy-MM-dd'
const timeFormat = 'HH:mm:ss.SSS'
const timeFormatHMS = 'HH:mm:ss'
const dateTimeFormat = `${dateFormat} ${timeFormat}`
const dateTimeFormatHMS = `${dateFormat} ${timeFormatHMS}`

// Plain functions, callable without the mixin (e.g. useTimeFilters). A
// timeZone of 'local' (or none) means the browser's time zone.

export function parseDateTime(dateString, timeZone) {
  if (dateString.includes(' ')) {
    dateString = dateString.replace(' ', 'T')
  }
  if (timeZone && timeZone === 'UTC') {
    dateString += 'Z'
  }
  return Date.parse(dateString)
}

// Convert a UTC stamp into a local time
export function formatUtcToLocal(date, timeZone) {
  // Default to local time if the timezone isn't set
  if (!timeZone || timeZone === 'local') {
    // subtrack off the timezone offset to get it back to local time
    return format(subMinutes(date, date.getTimezoneOffset()), dateTimeFormat)
  } else {
    return format(date, dateTimeFormat)
  }
}

export function formatDateTime(date, timeZone) {
  // Default to local time if the timezone isn't set
  if (!timeZone || timeZone === 'local') {
    return format(date, dateTimeFormat)
  } else {
    return formatInTimeZone(date, timeZone, dateTimeFormat)
  }
}

export function formatDateTimeHMS(date, timeZone) {
  // Default to local time if the timezone isn't set
  if (!timeZone || timeZone === 'local') {
    return format(date, dateTimeFormatHMS)
  } else {
    return formatInTimeZone(date, timeZone, dateTimeFormatHMS)
  }
}

export function formatDate(date, timeZone) {
  // Default to local time if the timezone isn't set
  if (!timeZone || timeZone === 'local') {
    return format(date, dateFormat)
  } else {
    return formatInTimeZone(date, timeZone, dateFormat)
  }
}

export function formatTime(date, timeZone, formatString = timeFormat) {
  // Default to local time if the timezone isn't set
  if (!timeZone || timeZone === 'local') {
    return format(date, formatString)
  } else {
    return formatInTimeZone(date, timeZone, formatString)
  }
}

export function formatTimeHMS(date, timeZone) {
  return formatTime(date, timeZone, timeFormatHMS)
}

export function formatTimestamp(timestamp, timeZone) {
  return formatDateTime(parseISO(timestamp), timeZone)
}

export function formatSeconds(secs, timeZone) {
  return formatDateTime(new Date(secs * 1000), timeZone)
}

export function formatNanoseconds(nanoSecs, timeZone) {
  return formatDateTime(new Date(parseInt(nanoSecs) / 1000000), timeZone)
}

// The Options API mixin. formatDate and formatTime have always used the
// component's own timeZone outside local time, so the mixin keeps that.
export default {
  methods: {
    parseDateTime,
    formatUtcToLocal,
    formatDateTime,
    formatDateTimeHMS,
    formatDate: function (date, timeZone) {
      if (!timeZone || timeZone === 'local') return formatDate(date, timeZone)
      return formatDate(date, this.timeZone)
    },
    formatTime: function (date, timeZone, formatString = timeFormat) {
      if (!timeZone || timeZone === 'local') {
        return formatTime(date, timeZone, formatString)
      }
      return formatTime(date, this.timeZone, formatString)
    },
    formatTimeHMS: function (date, timeZone) {
      return this.formatTime(date, timeZone, timeFormatHMS)
    },
    formatTimestamp,
    formatSeconds,
    formatNanoseconds,
  },
}
