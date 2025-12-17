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
    <v-dialog v-model="show" persistent width="600" @keydown.esc="clearHandler">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span v-if="metadata">Update Metadata</span>
          <span v-else>Create Metadata</span>
          <v-spacer />
          <v-btn
            icon="mdi-close-box"
            variant="text"
            density="compact"
            data-test="close-metadata-icon"
            @click="clearHandler"
          />
        </v-toolbar>
        <v-stepper
          v-model="dialogStep"
          editable
          :items="['Metadata Times', 'Metadata Input']"
        >
          <template v-if="dialogStep === 2" #actions>
            <v-row class="ma-0 px-6 pb-4">
              <v-btn variant="text" @click="() => (dialogStep -= 1)">
                Previous
              </v-btn>
              <v-spacer />
              <v-btn variant="outlined" class="mr-4" @click="clearHandler">
                Cancel
              </v-btn>
              <v-btn
                type="submit"
                color="primary"
                :disabled="!!error"
                @click.prevent="submitHandler"
              >
                Ok
              </v-btn>
            </v-row>
          </template>

          <template #item.1>
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
              </div>
            </v-card-text>
          </template>

          <template #item.2>
            <v-card-text>
              <div class="pa-2">
                <div style="min-height: 200px">
                  <metadata-input-form v-model="metadataVals" />
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
import { Api } from '@openc3/js-common/services'
import { TimeFilters } from '@/util'
import ColorSelectForm from './ColorSelectForm.vue'
import CreateDialog from './CreateDialog'
import MetadataInputForm from './MetadataInputForm.vue'

export default {
  components: {
    ColorSelectForm,
    MetadataInputForm,
  },
  mixins: [CreateDialog, TimeFilters],
  props: {
    modelValue: Boolean,
    metadata: {
      type: Object,
      default: null,
    },
  },
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
  mounted: function () {
    this.updateValues()
  },
  methods: {
    updateValues: function () {
      this.dialogStep = 1
      if (this.metadata) {
        const sDate = new Date(this.metadata.start * 1000)
        this.startDate = this.formatDate(sDate, this.timeZone)
        this.startTime = this.formatTimeHMS(sDate, this.timeZone)
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
    clearHandler: function () {
      this.show = !this.show
    },
    submitHandler() {
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
