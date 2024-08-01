<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addstopums as found in the LICENSE.txt
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
-->

<template>
  <v-dialog v-model="show" width="600">
    <v-card>
      <form @submit.prevent="updateActivity">
        <v-system-bar>
          <v-spacer />
          <span>
            Update activity: {{ activity.name }}/{{ activity.start }}
          </span>
          <v-spacer />
          <v-tooltip top>
            <template v-slot:activator="{ on, attrs }">
              <div v-on="on" v-bind="attrs">
                <v-icon data-test="close-activity-icon" @click="cancelActivity">
                  mdi-close-box
                </v-icon>
              </div>
            </template>
            <span> Close </span>
          </v-tooltip>
        </v-system-bar>
        <v-stepper v-model="dialogStep" vertical non-linear>
          <v-stepper-step editable step="1">
            Input start time, stop time
          </v-stepper-step>
          <v-stepper-content step="1">
            <v-card-text>
              <div class="pa-3">
                <v-row dense>
                  <v-text-field
                    v-model="startDate"
                    type="date"
                    label="Start Date"
                    class="mx-1"
                    :rules="[rules.required]"
                    data-test="activity-start-date"
                  />
                  <v-text-field
                    v-model="startTime"
                    type="time"
                    step="1"
                    label="Start Time"
                    class="mx-1"
                    :rules="[rules.required]"
                    data-test="activity-start-time"
                  />
                </v-row>
                <v-row dense>
                  <v-text-field
                    v-model="stopDate"
                    type="date"
                    label="End Date"
                    class="mx-1"
                    :rules="[rules.required]"
                    data-test="activity-stop-date"
                  />
                  <v-text-field
                    v-model="stopTime"
                    type="time"
                    step="1"
                    label="End Time"
                    class="mx-1"
                    :rules="[rules.required]"
                    data-test="activity-stop-time"
                  />
                </v-row>
                <v-row style="margin-top: 0px">
                  <v-col>
                    <v-radio-group
                      v-model="utcOrLocal"
                      row
                      hide-details
                      class="mt-0"
                    >
                      <v-radio label="LST" value="loc" data-test="lst-radio" />
                      <v-radio label="UTC" value="utc" data-test="utc-radio" />
                    </v-radio-group>
                  </v-col>
                  <v-col>
                    <v-checkbox
                      style="padding-top: 0px; margin-top: 0px"
                      v-model="recurring"
                      label="Recurring"
                      hide-details
                      data-test="recurring"
                      disabled
                    >
                    </v-checkbox>
                  </v-col>
                </v-row>
                <v-row v-if="recurring">
                  <v-col><div class="repeat">Repeat every</div></v-col>
                  <v-col>
                    <v-text-field
                      v-model="frequency"
                      dense
                      outlined
                      single-line
                      hide-details
                      disabled
                  /></v-col>
                  <v-col>
                    <v-select
                      :items="timeSpans"
                      v-model="timeSpan"
                      style="primary"
                      hide-details
                      dense
                      outlined
                      disabled
                      data-test="cmd-param-select"
                    />
                  </v-col>
                </v-row>
                <v-row v-if="recurring" style="padding-bottom: 10px">
                  <v-col><div class="repeat">Ending</div></v-col>
                  <v-col>
                    <v-text-field
                      v-model="recurringEndDate"
                      type="date"
                      label="End Date"
                      class="mx-1"
                      disabled
                      :rules="[rules.required]"
                      data-test="recurring-end-date"
                  /></v-col>
                  <v-col>
                    <v-text-field
                      v-model="recurringEndTime"
                      type="time"
                      step="1"
                      label="End Time"
                      class="mx-1"
                      disabled
                      :rules="[rules.required]"
                      data-test="recurrning-end-time"
                  /></v-col>
                </v-row>
                <v-row>
                  <span
                    class="ma-2 red--text"
                    v-show="timeError"
                    v-text="timeError"
                  />
                </v-row>
                <v-row class="mt-2">
                  <v-spacer />
                  <v-btn
                    @click="dialogStep = 2"
                    data-test="update-activity-step-two-btn"
                    color="success"
                    :disabled="!!timeError"
                  >
                    Continue
                  </v-btn>
                </v-row>
              </div>
            </v-card-text>
          </v-stepper-content>
          <v-stepper-step editable step="2">
            Activity type Input
          </v-stepper-step>
          <v-stepper-content step="2">
            <v-card-text>
              <div class="pa-3">
                <v-select v-model="kind" :items="types" label="Activity Type" />
                <div v-if="kind === 'COMMAND'">
                  <v-text-field
                    v-model="activityData"
                    type="text"
                    label="Command Input"
                    placeholder="INST COLLECT with TYPE 0, DURATION 1, OPCODE 171, TEMP 0"
                    prefix="cmd('"
                    suffix="')"
                    hint="Timeline runs commands with cmd_no_hazardous_check"
                    data-test="activity-cmd"
                  />
                </div>
                <div v-else-if="kind === 'SCRIPT'">
                  <script-chooser v-model="activityData" @file="fileHandler" />
                  <environment-chooser v-model="activityEnvironment" />
                </div>
                <div v-else>
                  <span class="ma-2"> No required input </span>
                </div>
                <v-row v-show="typeError" class="mt-2">
                  <span class="ma-2 red--text" v-text="typeError" />
                </v-row>
                <v-row class="mt-2">
                  <v-spacer />
                  <v-btn
                    @click="cancelActivity"
                    outlined
                    class="mx-2"
                    data-test="update-activity-cancel-btn"
                  >
                    Cancel
                  </v-btn>
                  <v-btn
                    @click.prevent="updateActivity"
                    class="mx-2"
                    color="primary"
                    type="submit"
                    data-test="update-activity-submit-btn"
                    :disabled="!!timeError || !!typeError"
                  >
                    Update
                  </v-btn>
                </v-row>
              </div>
            </v-card-text>
          </v-stepper-content>
        </v-stepper>
      </form>
    </v-card>
  </v-dialog>
</template>

<script>
import { format } from 'date-fns'
import Api from '@openc3/tool-common/src/services/api'
import EnvironmentChooser from '@openc3/tool-common/src/components/EnvironmentChooser'
import ScriptChooser from '@openc3/tool-common/src/components/ScriptChooser'
import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters.js'

export default {
  components: {
    EnvironmentChooser,
    ScriptChooser,
  },
  props: {
    activity: {
      type: Object,
      required: true,
    },
    value: Boolean, // value is the default prop when using v-model
  },
  mixins: [TimeFilters],
  data() {
    return {
      dialogStep: 1,
      startDate: '',
      startTime: '',
      stopDate: '',
      stopTime: '',
      utcOrLocal: 'loc',
      kind: '',
      // Should match list in ActivityCreateDialog
      types: ['COMMAND', 'SCRIPT', 'RESERVE'],
      activityData: '',
      activityEnvironment: [],
      rules: {
        required: (value) => !!value || 'Required',
      },
      recurring: false,
      recurringEndDate: null,
      recurringEndTime: null,
      frequency: 90,
      timeSpan: 'minutes',
      timeSpans: ['minutes', 'hours', 'days'],
    }
  },
  watch: {
    show: function () {
      this.updateValues()
    },
  },
  computed: {
    timeError: function () {
      const now = new Date()
      const start = Date.parse(`${this.startDate}T${this.startTime}`)
      const stop = Date.parse(`${this.stopDate}T${this.stopTime}`)
      if (start === stop) {
        return 'Invalid start, stop time. Activity must have different start and stop times.'
      }
      if (now > start) {
        return 'Invalid start time. Activity must be in the future.'
      }
      if (start > stop) {
        return 'Invalid start time. Activity start before stop.'
      }
      return null
    },
    typeError: function () {
      if (this.kind !== 'RESERVE' && !this.activityData) {
        return 'No data is selected or inputted'
      }
      return null
    },
    show: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
  },
  methods: {
    changeKind: function (inputKind) {
      if (inputKind === this.kind) {
        return
      }
      this.kind = inputKind
      this.activityData = ''
    },
    fileHandler: function (event) {
      this.activityData = event ? event : null
    },
    updateValues: function () {
      const sDate = new Date(this.activity.start * 1000)
      const eDate = new Date(this.activity.stop * 1000)
      this.startDate = format(sDate, 'yyyy-MM-dd')
      this.startTime = format(sDate, 'HH:mm:ss')
      this.stopDate = format(eDate, 'yyyy-MM-dd')
      this.stopTime = format(eDate, 'HH:mm:ss')
      this.kind = this.activity.kind.toUpperCase()
      this.activityData = this.activity.data[this.activity.kind]
      this.activityEnvironment = this.activity.data.environment
      if (this.activity.recurring?.uuid) {
        this.recurring = true
        const rDate = new Date(this.activity.recurring.end * 1000)
        this.recurringEndDate = format(rDate, 'yyyy-MM-dd')
        this.recurringEndTime = format(rDate, 'HH:mm:ss')
        this.frequency = this.activity.recurring.frequency
        this.timeSpan = this.activity.recurring.span
      }
    },
    cancelActivity: function () {
      this.show = !this.show
    },
    updateActivity: function () {
      // Call the api to update the activity
      const start = this.toIsoString(
        Date.parse(`${this.startDate}T${this.startTime}`),
      )
      const stop = this.toIsoString(
        Date.parse(`${this.stopDate}T${this.stopTime}`),
      )
      const kind = this.kind.toLowerCase()
      let data = { environment: this.activityEnvironment }
      data[kind] = this.activityData
      const tName = this.activity.name
      const aStart = this.activity.start
      var recurring = {}
      if (this.recurring) {
        recurring = {
          frequency: this.frequency,
          span: this.timeSpan,
          end: this.toIsoString(
            Date.parse(`${this.recurringEndDate}T${this.recurringEndTime}`),
          ),
        }
      }
      Api.put(`/openc3-api/timeline/${tName}/activity/${aStart}`, {
        data: { start, stop, kind, data, recurring },
      })
        .then((response) => {
          const activityTime = this.generateDateTime(
            new Date(response.data.start * 1000),
          )
          this.$notify.normal({
            title: 'Updated Activity',
            body: `${activityTime} (${response.data.start}) on timeline: ${response.data.name}`,
          })
          this.$emit('update')
          this.show = !this.show
        })
        .catch((error) => {
          this.show = !this.show
        })
    },
  },
}
</script>

<style scoped>
.repeat {
  padding-top: 10px;
  text-align: right;
}
.v-stepper--vertical .v-stepper__content {
  width: auto;
  margin: 0px 0px 0px 36px;
  padding: 0px;
}
</style>
