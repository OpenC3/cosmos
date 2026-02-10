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
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog
    :model-value="modelValue"
    width="600"
    persistent
    @keydown.esc="cancelSettings"
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <v-card>
      <v-form v-model="formValid" @submit.prevent>
        <v-toolbar height="24">
          <v-spacer />
          <span>Telemetry Grapher Settings</span>
          <v-spacer />
        </v-toolbar>
        <v-card-text>
          <div class="pa-3">
            <v-row v-for="(item, key) in localSettings" :key="key">
              <v-text-field
                v-model.number="item.value"
                hide-details="auto"
                type="number"
                :rules="[rules.required, rules.min]"
                :label="item.title"
              />
            </v-row>
            <v-row>
              <span class="text-red">
                Increasing these values may cause issues
              </span>
            </v-row>
            <v-row>
              <v-spacer />
              <v-btn
                variant="outlined"
                class="mx-2"
                data-test="settings-cancel-btn"
                @click="cancelSettings"
              >
                Cancel
              </v-btn>
              <v-btn
                type="submit"
                color="primary"
                class="mx-2"
                :disabled="!formValid"
                data-test="settings-save-btn"
                @click="saveSettings"
              >
                Save
              </v-btn>
            </v-row>
          </div>
        </v-card-text>
      </v-form>
    </v-card>
  </v-dialog>
</template>

<script>
export default {
  props: {
    modelValue: {
      type: Boolean,
      default: false,
    },
    settings: {
      type: Object,
      required: true,
    },
  },
  emits: ['update:modelValue', 'save'],
  data() {
    return {
      formValid: true,
      localSettings: {},
      rules: {
        required: (value) => !!value || 'Required',
        min: (value) => value >= 1 || 'Must be at least 1',
      },
    }
  },
  watch: {
    modelValue: {
      immediate: true,
      handler(val) {
        if (val) {
          // Create a deep copy of settings when dialog opens
          this.localSettings = {}
          for (const key in this.settings) {
            this.localSettings[key] = {
              title: this.settings[key].title,
              value: this.settings[key].value,
            }
          }
        }
      },
    },
  },
  methods: {
    saveSettings() {
      // Emit save event with the new values
      const newValues = {}
      for (const key in this.localSettings) {
        newValues[key] = this.localSettings[key].value
      }
      this.$emit('save', newValues)
      this.$emit('update:modelValue', false)
    },
    cancelSettings() {
      this.$emit('update:modelValue', false)
    },
  },
}
</script>
