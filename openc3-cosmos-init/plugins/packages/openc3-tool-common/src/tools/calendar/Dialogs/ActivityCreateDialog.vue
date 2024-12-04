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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-dialog persistent v-model="show" width="600">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span v-if="activity">Edit Activity</span>
          <span v-else>Create Activity</span>
          <v-spacer />
          <v-tooltip location="top">
            <template v-slot:activator="{ props }">
              <div v-bind="props">
                <v-icon data-test="close-note-icon" @click="clearHandler">
                  mdi-close-box
                </v-icon>
              </div>
            </template>
            <span> Close </span>
          </v-tooltip>
        </v-toolbar>
        <v-stepper
          v-model="dialogStep"
          editable
          :items="['Activity Times', 'Activity Type']"
        >
          <template v-if="dialogStep === 2" v-slot:actions>
            <v-row class="ma-0 px-6 pb-4">
              <v-btn @click="() => (dialogStep -= 1)" variant="text">
                Previous
              </v-btn>
              <v-spacer />
              <v-btn @click="clearHandler" variant="outlined" class="mr-4">
                Cancel
              </v-btn>
              <v-btn
                @click.prevent="submitHandler"
                type="submit"
                color="primary"
                :disabled="!!error"
              >
                Ok
              </v-btn>
            </v-row>
          </template>

          <template v-slot:item.1>
            <v-card-text>
              <div class="pr-2">
                <v-select
                  density="compact"
                  hide-details
                  variant="outlined"
                  v-model="timeline"
                  :items="timelineNames"
                  label="Timeline"
                  data-test="activity-select-timeline"
                  class="pb-2"
                >
                </v-select>
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
                    v-model="endDate"
                    type="date"
                    label="End Date"
                    class="mx-1"
                    :rules="[rules.required]"
                    data-test="activity-end-date"
                  />
                  <v-text-field
                    v-model="endTime"
                    type="time"
                    step="1"
                    label="End Time"
                    class="mx-1"
                    :rules="[rules.required]"
                    data-test="activity-end-time"
                  />
                </v-row>
                <v-row class="pl-3">
                  <v-checkbox
                    v-model="recurring"
                    :disabled="!!activity"
                    label="Recurring"
                    hide-details
                    data-test="recurring"
                  >
                  </v-checkbox>
                </v-row>
                <v-row v-if="recurring">
                  <v-col><div class="repeat">Repeat every</div></v-col>
                  <v-col>
                    <v-text-field
                      v-model="frequency"
                      :disabled="!!activity"
                      density="compact"
                      variant="outlined"
                      single-line
                      hide-details
                      data-test="recurring-frequency"
                  /></v-col>
                  <v-col>
                    <v-select
                      v-model="timeSpan"
                      :disabled="!!activity"
                      :items="timeSpans"
                      style="primary"
                      hide-details
                      density="compact"
                      variant="outlined"
                      data-test="recurring-span"
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
                      :rules="[rules.required]"
                      :disabled="!!activity"
                      data-test="recurring-end-date"
                  /></v-col>
                  <v-col>
                    <v-text-field
                      v-model="recurringEndTime"
                      type="time"
                      step="1"
                      label="End Time"
                      class="mx-1"
                      :rules="[rules.required]"
                      :disabled="!!activity"
                      data-test="recurring-end-time"
                  /></v-col>
                </v-row>
                <v-row>
                  <span
                    class="ma-2 text-red"
                    v-show="timeError"
                    v-text="timeError"
                  />
                </v-row>
              </div>
            </v-card-text>
          </template>

          <template v-slot:item.2>
            <v-card-text>
              <div class="pr-2">
                <v-select
                  density="compact"
                  hide-details
                  variant="outlined"
                  v-model="kind"
                  :items="types"
                  label="Activity Type"
                  data-test="activity-select-type"
                  class="pb-2"
                >
                </v-select>
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
                <div class="ma-3" v-else-if="kind === 'SCRIPT'">
                  <script-chooser @file="fileHandler" />
                  <environment-chooser v-model="activityEnvironment" />
                </div>
                <div v-else>
                  <span class="ma-2"> No required input </span>
                </div>
                <v-row v-show="typeError" class="mt-2">
                  <span class="ma-2 text-red" v-text="typeError" />
                </v-row>
              </div>
            </v-card-text>
          </template>
        </v-stepper>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import Api from '@openc3/tool-common/src/services/api'
import EnvironmentChooser from '@openc3/tool-common/src/components/EnvironmentChooser'
import ScriptChooser from '@openc3/tool-common/src/components/ScriptChooser'
import CreateDialog from '@openc3/tool-common/src/tools/calendar/Dialogs/CreateDialog.js'
import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters.js'

export default {
  components: {
    EnvironmentChooser,
    ScriptChooser,
  },
  props: {
    modelValue: Boolean,
    timelines: {
      type: Array,
      required: true,
    },
    activity: {
      type: Object,
      default: null,
    },
  },
  mixins: [CreateDialog, TimeFilters],
  data() {
    return {
      timeline: null,
      dialogStep: 1,
      kind: '',
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
  mounted: function () {
    this.updateValues()
  },
  computed: {
    timeError: function () {
      const now = new Date()
      const start = Date.parse(`${this.startDate}T${this.startTime}`)
      const end = Date.parse(`${this.endDate}T${this.endTime}`)
      if (start === end) {
        return 'Invalid start, end time. Activity must have different start and end times.'
      }
      if (now > start) {
        return 'Invalid start time. Activity must be in the future.'
      }
      if (start > end) {
        return 'Invalid start time. Activity start before end.'
      }
      return null
    },
    typeError: function () {
      if (!this.timeline) {
        return 'Activity must have a timeline selected.'
      }
      if (this.kind !== 'RESERVE' && !this.activityData) {
        return 'No data is selected or inputted'
      }
      return null
    },
    timelineNames: function () {
      return this.timelines.map((timeline) => {
        return timeline.name
      })
    },
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
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
      this.activityData = event
    },
    updateValues: function () {
      this.dialogStep = 1
      if (this.activity) {
        this.timeline = this.activity.name
        const sDate = new Date(this.activity.start * 1000)
        const eDate = new Date(this.activity.stop * 1000)
        this.startDate = this.formatDate(sDate, this.timeZone)
        this.startTime = this.formatTimeHMS(sDate, this.timeZone)
        this.endDate = this.formatDate(eDate, this.timeZone)
        this.endTime = this.formatTimeHMS(eDate, this.timeZone)
        this.kind = this.activity.kind.toUpperCase()
        this.activityData = this.activity.data[this.activity.kind]
        this.activityEnvironment = this.activity.data.environment
        if (this.activity.recurring?.uuid) {
          this.recurring = true
          const rDate = new Date(this.activity.recurring.end * 1000)
          this.recurringEndDate = this.formatDate(rDate, this.timeZone)
          this.recurringEndTime = this.formatTimeHMS(rDate, this.timeZone)
          this.frequency = this.activity.recurring.frequency
          this.timeSpan = this.activity.recurring.span
        }
      } else {
        this.calcStartDateTime()
        this.recurringEndDate = this.startDate
        this.recurringEndTime = this.startTime
        this.kind = ''
        this.activityData = ''
        this.activityEnvironment = []
        this.timeline = this.timelineNames[0]
      }
    },
    clearHandler: function () {
      this.show = !this.show
    },
    submitHandler() {
      // Call the api to create a new activity to add to the activities array
      let start = null
      let stop = null // API takes stop instead of end
      let recurringEnd = null
      if (this.timeZone === 'local') {
        start = new Date(this.startDate + ' ' + this.startTime).toISOString()
        stop = new Date(this.endDate + ' ' + this.endTime).toISOString()
        if (this.recurring) {
          recurringEnd = new Date(
            this.recurringEndDate + ' ' + this.recurringEndTime,
          ).toISOString()
        }
      } else {
        start = new Date(
          this.startDate + ' ' + this.startTime + 'Z',
        ).toISOString()
        stop = new Date(this.endDate + ' ' + this.endTime + 'Z').toISOString()
        if (this.recurring) {
          recurringEnd = new Date(
            this.recurringEndDate + ' ' + this.recurringEndTime + 'Z',
          ).toISOString()
        }
      }
      const kind = this.kind.toLowerCase()
      let data = { environment: this.activityEnvironment }
      data[kind] = this.activityData
      let recurring = {}
      if (this.recurring) {
        recurring = {
          frequency: this.frequency,
          span: this.timeSpan,
          end: recurringEnd,
        }
      }
      if (this.activity) {
        Api.put(
          `/openc3-api/timeline/${this.activity.name}/activity/${this.activity.start}`,
          {
            data: { start, stop, kind, data, recurring },
          },
        )
          .then((response) => {
            const activityTime = this.formatSeconds(
              new Date(response.data.start * 1000),
            )
            this.$notify.normal({
              title: 'Updated Activity',
              body: `${activityTime} (${response.data.start}) on timeline: ${response.data.name}`,
            })
            this.$emit('update', response.data)
            this.show = !this.show
          })
          .catch((error) => {
            this.show = !this.show
          })
      } else {
        Api.post(`/openc3-api/timeline/${this.timeline}/activities`, {
          data: { start, stop, kind, data, recurring },
        })
          .then((response) => {
            const activityTime = this.formatSeconds(
              new Date(response.data.start * 1000),
            )
            this.$notify.normal({
              title: 'Created Activity',
              body: `${activityTime} (${response.data.start}) on timeline: ${response.data.name}`,
            })
            this.$emit('update', response.data)
            this.show = !this.show
          })
          .catch((error) => {
            this.show = !this.show
          })
      }
      // We don't do the $emit or set show here because it has to be in the callback
      this.clearHandler()
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
