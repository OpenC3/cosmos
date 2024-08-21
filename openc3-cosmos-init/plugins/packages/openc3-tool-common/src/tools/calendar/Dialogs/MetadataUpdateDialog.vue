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

<!-- TODO: Combine with MetadataCreateDialog -->
<template>
  <div>
    <v-dialog persistent v-model="show" width="600">
      <v-card>
        <form @submit.prevent="updateMetadata">
          <v-system-bar>
            <v-spacer />
            <span>Update Metadata</span>
            <v-spacer />
            <v-tooltip top>
              <template v-slot:activator="{ on, attrs }">
                <div v-on="on" v-bind="attrs">
                  <v-icon data-test="close-metadata-icon" @click="show = !show">
                    mdi-close-box
                  </v-icon>
                </div>
              </template>
              <span> Close </span>
            </v-tooltip>
          </v-system-bar>
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
                      data-test="start-date"
                    />
                    <v-text-field
                      v-model="startTime"
                      type="time"
                      step="1"
                      label="Start Time"
                      class="mx-1"
                      :rules="[rules.required]"
                      data-test="start-time"
                    />
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
                      data-test="create-metadata-step-two-btn"
                      color="success"
                      :disabled="!!timeError"
                    >
                      Continue
                    </v-btn>
                  </v-row>
                </div>
              </v-card-text>
            </v-stepper-content>
            <v-stepper-step editable step="2"> Metadata input </v-stepper-step>
            <v-stepper-content step="2">
              <v-card-text>
                <div class="pa-2">
                  <div style="min-height: 200px">
                    <metadata-input-form v-model="metadata" />
                  </div>
                  <v-row v-show="typeError">
                    <span class="ma-2 red--text" v-text="typeError" />
                  </v-row>
                  <v-row class="mt-2">
                    <v-spacer />
                    <v-btn
                      @click="show = !show"
                      outlined
                      class="mx-2"
                      data-test="update-metadata-cancel-btn"
                    >
                      Cancel
                    </v-btn>
                    <v-btn
                      @click.prevent="updateMetadata"
                      class="mx-2"
                      color="primary"
                      type="submit"
                      data-test="update-metadata-submit-btn"
                      :disabled="!!timeError || !!typeError"
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
import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters.js'
import ColorSelectForm from '@openc3/tool-common/src/tools/calendar/Forms/ColorSelectForm'
import MetadataInputForm from '@openc3/tool-common/src/tools/calendar/Forms/MetadataInputForm'

export default {
  components: {
    ColorSelectForm,
    MetadataInputForm,
  },
  props: {
    metadataObj: {
      type: Object,
      required: true,
    },
    value: Boolean, // value is the default prop when using v-model
  },
  mixins: [TimeFilters],
  data() {
    return {
      scope: window.openc3Scope,
      dialogStep: 1,
      startDate: '',
      startTime: '',
      color: '',
      metadata: [],
      rules: {
        required: (value) => !!value || 'Required',
      },
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
      if (now < start) {
        return 'Invalid start time. Can not be in the future'
      }
      return null
    },
    typeError: function () {
      if (this.metadata.length < 1) {
        return 'Please enter a value in the metadata table.'
      }
      const emptyKeyValue = this.metadata.find(
        (meta) => meta.key === '' || meta.value === ''
      )
      if (emptyKeyValue) {
        return 'Missing or empty key, value in the metadata table.'
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
    updateValues: function () {
      const sDate = new Date(this.metadataObj.start * 1000)
      this.startDate = format(sDate, 'yyyy-MM-dd')
      this.startTime = format(sDate, 'HH:mm:ss')
      this.metadata = Object.keys(this.metadataObj.metadata).map((k) => {
        return { key: k, value: this.metadataObj.metadata[k] }
      })
      this.color = this.metadataObj.color
    },
    updateMetadata: function () {
      const color = this.color
      const metadata = this.metadata.reduce((result, element) => {
        result[element.key] = element.value
        return result
      }, {})
      const start = this.toIsoString(
        Date.parse(`${this.startDate}T${this.startTime}`)
      )
      Api.put(`/openc3-api/metadata/${this.metadataObj.start}`, {
        data: { start, color, metadata },
      }).then((response) => {
        this.$notify.normal({
          title: 'Updated Metadata',
          body: `Metadata updated: (${response.data.start})`,
        })
        console.log('metadata update emit')
        this.$emit('update', { ...response.data.start, color, metadata })
      })
      this.$emit('close')
      this.show = !this.show
      this.updateValues()
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
