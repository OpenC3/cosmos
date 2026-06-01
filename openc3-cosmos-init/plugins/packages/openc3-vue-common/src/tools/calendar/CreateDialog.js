/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { add, format, parse } from 'date-fns'

export default {
  props: {
    date: {
      type: String,
    },
    time: {
      type: String,
    },
    timeZone: {
      type: String,
    },
  },
  data() {
    return {
      startDate: '',
      startTime: '',
      endDate: '',
      endTime: '',
    }
  },
  methods: {
    calcStartDateTime: function () {
      if (this.date) {
        this.startDate = this.date
        this.endDate = this.date
      } else {
        this.startDate = this.formatDate(new Date(), this.timeZone)
        this.endDate = this.startDate
      }
      let ms = 1000 * 60 * 30 // 30 min
      let start = null
      if (this.time) {
        // this.time is already in the display timezone; parse/format roundtrip
        // in local time preserves the HH:mm:ss the user clicked on.
        start = parse(this.time, 'HH:mm:ss', new Date())
        // Round down so the start is the beginning of the time box where they clicked
        start = new Date(Math.floor(start.getTime() / ms) * ms)
        this.startTime = format(start, 'HH:mm:ss')
        this.endTime = format(add(start, { minutes: 30 }), 'HH:mm:ss')
      } else {
        // Round up so the start is in the future
        start = new Date(Math.ceil(new Date().getTime() / ms) * ms)
        const end = add(start, { minutes: 30 })
        this.startTime = this.formatTimeHMS(start, this.timeZone)
        this.endTime = this.formatTimeHMS(end, this.timeZone)
        // Re-derive the dates from the rounded values. Rounding up (or the
        // +30min end) can roll past midnight -- e.g. at 23:52 the next 30-min
        // boundary is 00:00 the following day. If the dates were left on
        // "today" (set above) the start would be in the past, and the activity
        // form (which requires a future start) could never be submitted.
        this.startDate = this.formatDate(start, this.timeZone)
        this.endDate = this.formatDate(end, this.timeZone)
      }
    },
  },
}
