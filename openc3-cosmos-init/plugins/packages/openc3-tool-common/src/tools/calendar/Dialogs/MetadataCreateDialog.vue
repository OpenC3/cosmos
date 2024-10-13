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
        <form @submit.prevent="createMetadata">
          <v-toolbar height="24">
            <v-spacer />
            <span v-if="metadata">Update Metadata</span>
            <span v-else>Create Metadata</span>
            <v-spacer />
            <v-tooltip location="top">
              <template v-slot:activator="{ props }">
                <div v-bind="props">
                  <v-icon data-test="close-metadata-icon" @click="show = !show">
                    mdi-close-box
                  </v-icon>
                </div>
              </template>
              <span>Close</span>
            </v-tooltip>
          </v-toolbar>
          <v-stepper v-model="dialogStep" vertical non-linear>
            <v-stepper-step editable step="1">
              Input start time
            </v-stepper-step>
            <v-stepper-content step="1">
              <v-card-text>
                <div class="pa-2">
                  <color-select-form v-model="color" />
                  <v-row dense>
                    <v-text-field
                      v-model="startDate"
                      type="date"
                      label="Start Date"
                      class="mx-1"
                      :rules="[rules.required]"
                      data-test="metadata-start-date"
                    />
                    <v-text-field
                      v-model="startTime"
                      type="time"
                      step="1"
                      label="Start Time"
                      class="mx-1"
                      :rules="[rules.required]"
                      data-test="metadata-start-time"
                    />
                  </v-row>
                  <v-row class="mt-2">
                    <v-spacer />
                    <v-btn
                      @click="dialogStep = 2"
                      data-test="metadata-step-two-btn"
                      color="success"
                    >
                      Continue
                    </v-btn>
                  </v-row>
                </div>
              </v-card-text>
            </v-stepper-content>
            <v-stepper-step editable step="2">Metadata Input</v-stepper-step>
            <v-stepper-content step="2">
              <v-card-text>
                <div class="pa-2">
                  <div style="min-height: 200px">
                    <metadata-input-form v-model="metadataVals" />
                  </div>
                  <v-row v-show="typeError">
                    <span class="ma-2 text-red" v-text="typeError" />
                  </v-row>
                  <v-row class="mt-2">
                    <v-spacer />
                    <v-btn
                      @click="show = !show"
                      variant="outlined"
                      class="mx-2"
                      data-test="metadata-cancel-btn"
                    >
                      Cancel
                    </v-btn>
                    <v-btn
                      @click.prevent="createMetadata"
                      class="mx-2"
                      color="primary"
                      type="submit"
                      data-test="metadata-submit-btn"
                      :disabled="!!typeError"
                    >
                      Ok
                    </v-btn>
                  </v-row>
                </div>
              </v-card-text>
            </v-stepper-content>
          </v-stepper>
        </form>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import Api from '@openc3/tool-common/src/services/api'
import CreateDialog from '@openc3/tool-common/src/tools/calendar/Dialogs/CreateDialog.js'
import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters.js'
import ColorSelectForm from '@openc3/tool-common/src/tools/calendar/Forms/ColorSelectForm'
import MetadataInputForm from '@openc3/tool-common/src/tools/calendar/Forms/MetadataInputForm'

export default {
  components: {
    ColorSelectForm,
    MetadataInputForm,
  },
  props: {
    modelValue: Boolean,
    metadata: {
      type: Object,
      default: null,
    },
  },
  mixins: [CreateDialog, TimeFilters],
  data() {
    return {
      dialogStep: 1,
      color: '#003784',
      metadataVals: [],
      rules: {
        required: (value) => !!value || 'Required',
      },
    }
  },
  mounted: function () {
    this.updateValues()
  },
  computed: {
    typeError: function () {
      if (!this.color) {
        return 'A color is required.'
      }
      if (this.metadataVals.length < 1) {
        return 'Please enter a value in the metadata table.'
      }
      const emptyKeyValue = this.metadataVals.find(
        (meta) => meta.key === '' || meta.value === '',
      )
      if (emptyKeyValue) {
        return 'Missing or empty key, value in the metadata table.'
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
      if (this.metadata) {
        const sDate = new Date(this.metadata.start * 1000)
        this.startDate = this.formatDate(sDate, this.timeZone)
        this.startTime = this.formatTime(sDate, this.timeZone)
        this.color = this.metadata.color
        this.metadataVals = Object.keys(this.metadata.metadata).map((k) => {
          return { key: k, value: this.metadata.metadata[k] }
        })
      } else {
        this.calcStartDateTime()
        this.color = '#003784'
        this.metadataVals = []
      }
    },
    createMetadata: function () {
      const color = this.color
      const metadata = this.metadataVals.reduce((result, element) => {
        result[element.key] = element.value
        return result
      }, {})
      const data = { color, metadata }
      if (this.timeZone === 'local') {
        data.start = new Date(
          this.startDate + ' ' + this.startTime,
        ).toISOString()
      } else {
        data.start = new Date(
          this.startDate + ' ' + this.startTime + 'Z',
        ).toISOString()
      }
      if (this.metadata) {
        Api.put(`/openc3-api/metadata/${this.metadata.start}`, {
          data,
        }).then((response) => {
          this.$notify.normal({
            title: 'Updated Metadata',
            body: `Metadata updated: (${response.data.start})`,
          })
          this.$emit('update', response.data)
          this.show = !this.show
        })
      } else {
        Api.post('/openc3-api/metadata', {
          data,
        }).then((response) => {
          this.$notify.normal({
            title: 'Created new Metadata',
            body: `Metadata: (${response.data.start})`,
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
