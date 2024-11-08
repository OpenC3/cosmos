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
          <span v-if="note">Update Note</span>
          <span v-else>Create Note</span>
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
          :items="['Note Times', 'Note Input']"
        >
          <template v-if="dialogStep === 2" v-slot:actions>
            <v-row class="ma-0 px-6 pb-4">
              <v-btn @click="() => (dialogStep -= 1)" variant="text">
                Previous
              </v-btn>
              <v-spacer />
              <v-btn
                @click="clearHandler"
                variant="outlined"
                class="mr-4"
                data-test="trigger-create-cancel-btn"
              >
                Cancel
              </v-btn>
              <v-btn
                @click.prevent="submitHandler"
                type="submit"
                color="primary"
                data-test="trigger-create-submit-btn"
                :disabled="!!error"
              >
                Ok
              </v-btn>
            </v-row>
          </template>

          <template v-slot:item.1>
            <v-card-text>
              <div class="pa-2">
                <v-row dense>
                  <v-text-field
                    v-model="startDate"
                    type="date"
                    label="Start Date"
                    class="mx-1"
                    :rules="[rules.required]"
                    data-test="note-start-date"
                  />
                  <v-text-field
                    v-model="startTime"
                    type="time"
                    step="1"
                    label="Start Time"
                    class="mx-1"
                    :rules="[rules.required]"
                    data-test="note-start-time"
                  />
                </v-row>
                <v-row dense>
                  <v-text-field
                    v-model="endDate"
                    type="date"
                    label="End Date"
                    class="mx-1"
                    :rules="[rules.required]"
                    data-test="note-end-date"
                  />
                  <v-text-field
                    v-model="endTime"
                    type="time"
                    step="1"
                    label="End Time"
                    class="mx-1"
                    :rules="[rules.required]"
                    data-test="note-end-time"
                  />
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
              <div class="pa-2">
                <div>
                  <color-select-form v-model="color" />
                </div>
                <div>
                  <v-text-field
                    v-model="description"
                    type="text"
                    label="Note Description"
                    data-test="note-description"
                  />
                </div>
                <v-row v-show="typeError">
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
import CreateDialog from '@openc3/tool-common/src/tools/calendar/Dialogs/CreateDialog.js'
import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters.js'
import ColorSelectForm from '@openc3/tool-common/src/tools/calendar/Forms/ColorSelectForm'

export default {
  components: {
    ColorSelectForm,
  },
  props: {
    modelValue: Boolean,
    note: {
      type: Object,
    },
  },
  mixins: [CreateDialog, TimeFilters],
  data() {
    return {
      dialogStep: 1,
      description: '',
      color: '#8F3400',
      rules: {
        required: (value) => !!value || 'Required',
      },
    }
  },
  mounted: function () {
    this.updateValues()
  },
  computed: {
    timeError: function () {
      let start
      let end
      if (this.timeZone === 'local') {
        start = new Date(this.startDate + ' ' + this.startTime)
        end = new Date(this.endDate + ' ' + this.endTime)
      } else {
        start = new Date(this.startDate + ' ' + this.startTime + 'Z')
        end = new Date(this.endDate + ' ' + this.endTime + 'Z')
      }
      if (start === end) {
        return 'Invalid start, end time. Notes must have different start and end times.'
      }
      if (start > end) {
        return 'Invalid start time. Notes start before end.'
      }
      return null
    },
    typeError: function () {
      if (!this.color) {
        return 'A color is required.'
      }
      if (!this.description) {
        return 'A description is required for a valid note.'
      }
      return null
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
    updateValues: function () {
      this.dialogStep = 1
      if (this.note) {
        const sDate = new Date(this.note.start * 1000)
        this.startDate = this.formatDate(sDate, this.timeZone)
        this.startTime = this.formatTimeHMS(sDate, this.timeZone)
        const eDate = new Date(this.note.stop * 1000)
        this.endDate = this.formatDate(eDate, this.timeZone)
        this.endTime = this.formatTimeHMS(eDate, this.timeZone)
        this.color = this.note.color
        this.description = this.note.description
      } else {
        this.calcStartDateTime()
        this.color = '#8F3400'
        this.description = ''
      }
    },
    clearHandler: function () {
      this.show = !this.show
    },
    submitHandler() {
      let start
      let stop // API takes stop rather than end
      if (this.timeZone === 'local') {
        start = new Date(this.startDate + ' ' + this.startTime).toISOString()
        stop = new Date(this.endDate + ' ' + this.endTime).toISOString()
      } else {
        start = new Date(
          this.startDate + ' ' + this.startTime + 'Z',
        ).toISOString()
        stop = new Date(this.endDate + ' ' + this.endTime + 'Z').toISOString()
      }
      const color = this.color
      const description = this.description
      if (this.note) {
        Api.put(`/openc3-api/notes/${this.note.start}`, {
          data: { start, stop, color, description },
        }).then((response) => {
          const desc =
            response.data.description.length > 16
              ? `${response.data.description.substring(0, 16)}...`
              : response.data.description
          this.$notify.normal({
            title: 'Updated Note',
            body: `Note updated: (${response.data.start}): "${desc}"`,
          })
          this.$emit('update', response.data)
          this.show = !this.show
        })
      } else {
        Api.post('/openc3-api/notes', {
          data: { start, stop, color, description },
        }).then((response) => {
          const desc =
            response.data.description.length > 16
              ? `${response.data.description.substring(0, 16)}...`
              : response.data.description
          this.$notify.normal({
            title: 'Created new Note',
            body: `Note: (${response.data.start}) created: "${desc}"`,
          })
          this.$emit('update', response.data)
          this.show = !this.show
        })
      }
      // We don't do the $emit or set show here because it has to be in the callback
    },
  },
}
</script>

<style scoped>
.v-stepper--vertical .v-stepper__content {
  width: auto;
  margin: 0px 0px 0px 36px;
  padding: 0px;
}
</style>
