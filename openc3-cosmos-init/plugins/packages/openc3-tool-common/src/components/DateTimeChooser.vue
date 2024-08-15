<!--
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-row>
      <v-col>
        <v-menu
          close-on-content-click
          transition="scale-transition"
          offset-y
          max-width="290px"
          min-width="290px"
        >
          <template v-slot:activator="{ on }">
            <!-- TODO: Investigate using Date Chooser or something that better supports timezones -->
            <!-- We set the :name attribute to be unique to avoid auto-completion -->
            <v-text-field
              :label="dateLabel"
              :name="`date${Date.now()}`"
              :rules="dateRules"
              v-model="date"
              v-on="on"
              type="date"
              data-test="date-chooser"
            />
          </template>
        </v-menu>
      </v-col>
      <v-col>
        <!-- TODO: Investigate using Time Chooser or something that better supports timezones -->
        <!-- We set the :name attribute to be unique to avoid auto-completion -->
        <v-text-field
          :label="timeLabel"
          :name="`time${Date.now()}`"
          :rules="timeRules"
          v-model="time"
          type="time"
          step="1"
          @change="onChange"
          data-test="time-chooser"
        />
      </v-col>
    </v-row>
  </div>
</template>

<script>
import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters.js'
import { isValid, parse, toDate } from 'date-fns'

export default {
  props: {
    required: {
      type: Boolean,
      default: true,
    },
    dateTime: {
      type: Number,
      default: null,
    },
    dateLabel: {
      type: String,
      default: 'Date',
    },
    timeLabel: {
      type: String,
      default: 'Time',
    },
    timeZone: {
      type: String,
      default: 'local',
    },
  },
  mixins: [TimeFilters],
  data() {
    return {
      date: null,
      time: null,
      rules: {
        required: (value) => !!value || 'Required',
        date: (value) => {
          if (!value) return true
          try {
            return (
              isValid(parse(value, 'yyyy-MM-dd', new Date())) ||
              'Invalid date (YYYY-MM-DD)'
            )
          } catch (e) {
            return 'Invalid date (YYYY-MM-DD)'
          }
        },
        time: (value) => {
          if (!value) return true
          try {
            return (
              isValid(parse(value, 'HH:mm:ss', new Date())) ||
              'Invalid time (HH:MM:SS)'
            )
          } catch (e) {
            return 'Invalid time (HH:MM:SS)'
          }
        },
      },
    }
  },
  computed: {
    dateRules() {
      let result = [this.rules.date]
      if (this.time || this.required) {
        result.push(this.rules.required)
      }
      return result
    },
    timeRules() {
      let result = [this.rules.time]
      if (this.date || this.required) {
        result.push(this.rules.required)
      }
      return result
    },
  },
  created() {
    if (this.dateTime) {
      // let initialDate = toDate(this.dateTime / 1_000_000)
      // this.date = format(initialDate, 'yyyy-MM-dd')
      // this.time = format(initialDate, 'HH:mm:ss')

      let date = toDate(this.dateTime / 1_000_000)
      console.log(date)
      // this.date = this.formatDate(date, this.timeZone)
      // this.time = this.formatTime(date, this.timeZone)
      if (this.timeZone == 'local') {
        this.date = format(date, 'yyyy-MM-dd')
        this.time = format(date, 'HH:mm:ss.SSS')
      } else {
        this.date = formatInTimeZone(date, this.timeZone, 'yyyy-MM-dd')
        this.time = formatInTimeZone(date, this.timeZone, 'HH:mm:ss.SSS')
      }
    }
  },
  methods: {
    onChange() {
      if (!!this.date && !!this.time) {
        this.$emit('date-time', this.date + ' ' + this.time)
      } else {
        this.$emit('date-time', null)
      }
    },
  },
}
</script>
