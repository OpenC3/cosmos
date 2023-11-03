/*
# Copyright 2023 OpenC3, Inc.
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

import { add, format, parse } from 'date-fns'

export default {
  props: {
    date: {
      type: String,
    },
    time: {
      type: String,
    },
  },
  data() {
    return {
      startDate: '',
      startTime: '',
      stopDate: '',
      stopTime: '',
      utcOrLocal: 'loc',
    }
  },
  methods: {
    calcStartDateTime: function () {
      if (this.date) {
        this.startDate = this.date
        this.stopDate = this.date
      } else {
        this.startDate = format(new Date(), 'yyyy-MM-dd')
        this.stopDate = format(new Date(), 'yyyy-MM-dd')
      }
      let ms = 1000 * 60 * 30 // 30 min
      let start = null
      if (this.time) {
        start = parse(this.time, 'HH:mm:ss', new Date())
        // Round down so the start is the beginning of the time box where they clicked
        start = new Date(Math.floor(start.getTime() / ms) * ms)
      } else {
        // Round up so the start is in the future
        start = new Date(Math.ceil(new Date().getTime() / ms) * ms)
      }
      this.startTime = format(start, 'HH:mm:ss')
      this.stopTime = format(add(start, { minutes: 30 }), 'HH:mm:ss')
    },
  },
}
