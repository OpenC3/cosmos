<!--
# Copyright 2025 OpenC3, Inc.
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
-->

<template>
  <v-card>
    <v-card-title>Context Tag Settings</v-card-title>
    <v-card-subtitle>
      When enabled, this displays a Context Tag pill on the top right of the screen, with custom colors and text. 
      This can help differentiate environments.
    </v-card-subtitle>
    <v-alert v-model="errorLoading" type="error" closable density="compact">
      Error loading previous configuration due to {{ errorText }}
    </v-alert>
    <v-alert v-model="errorSaving" type="error" closable density="compact">
      Error saving due to {{ errorText }}
    </v-alert>
    <v-alert v-model="successSaving" type="success" closable density="compact">
      Saved! (Refresh the page to see changes)
    </v-alert>
    <v-card-text class="pb-0">
      <v-row dense>
        <v-col>
          <v-text-field
            label="Text"
            v-model="text"
            data-test="context-tag-text"
            :disabled="!displayContextTag"
          />
        </v-col>
      </v-row>
      <v-row dense>
        <v-col>
          <v-switch
            label="Display context tag"
            v-model="displayContextTag"
            color="primary"
            data-test="display-context-tag"
          />
        </v-col>
        <v-col>
          <v-select
            label="Background color"
            :items="colors"
            item-title="text"
            v-model="selectedBackgroundColor"
            data-test="context-tag-background-color"
          >
            <template v-slot:prepend-inner v-if="selectedBackgroundColor">
              <v-icon :color="selectedBackgroundColor"> mdi-square </v-icon>
            </template>
            <template v-slot:item="{ props, item }">
              <v-list-item v-bind="props" :value="item.text">
                <template v-slot:prepend>
                  <v-icon :color="item.value" v-if="item.value">
                    mdi-square
                  </v-icon>
                </template>
              </v-list-item>
            </template>
          </v-select>
        </v-col>
        <v-col>
          <v-text-field
            label="Custom background color"
            :hint="customColorHint"
            :disabled="selectedBackgroundColor !== false"
            v-model="customBackgroundColor"
            :rules="[rules.customColor]"
            data-test="context-tag-custom-background-color"
          >
            <template v-slot:prepend-inner>
              <v-icon
                v-show="!selectedBackgroundColor"
                :color="customBackgroundColor"
              >
                mdi-square
              </v-icon>
            </template>
          </v-text-field>
        </v-col>
        <v-col>
          <v-select
            label="Font color"
            :items="colors"
            item-title="text"
            v-model="selectedFontColor"
            data-test="context-tag-font-color"
          >
            <template v-slot:prepend-inner v-if="selectedFontColor">
              <v-icon v-show="selectedFontColor" :color="selectedFontColor">
                mdi-square
              </v-icon>
            </template>
            <template v-slot:item="{ props, item }">
              <v-list-item v-bind="props" :value="item.text">
                <template v-slot:prepend>
                  <v-icon :color="item.value" v-if="item.value">
                    mdi-square
                  </v-icon>
                </template>
              </v-list-item>
            </template>
          </v-select>
        </v-col>
        <v-col>
          <v-text-field
            label="Custom font color"
            :hint="customColorHint"
            :disabled="selectedFontColor !== false"
            v-model="customFontColor"
            :rules="[rules.customColor]"
            data-test="context-tag-custom-font-color"
          >
            <template v-slot:prepend-inner>
              <v-icon v-show="!selectedFontColor" :color="customFontColor">
                mdi-square
              </v-icon>
            </template>
          </v-text-field>
        </v-col>
      </v-row>
    </v-card-text>
    <v-card-actions>
      <v-btn
        :disabled="!formValid"
        @click="save"
        color="success"
        variant="text"
        data-test="save-context-tag"
      >
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import Settings from './settings.js'

const settingName = 'context_tag'
export default {
  mixins: [Settings],
  data() {
    return {
      text: '',
      displayContextTag: false,
      selectedBackgroundColor: '#009fa3',
      customBackgroundColor: '',
      selectedFontColor: 'white',
      customFontColor: '',
      customColorHint: 'Enter a 3 or 6-digit hex color code',
      colors: [
        {
          text: 'Teal',
          value: '#009fa3',
        },
        {
          text: 'Purple',
          value: '#6058a8',
        },
        {
          text: 'Pink',
          value: '#81009a',
        },
        {
          text: 'Orange',
          value: '#af420a',
        },
        {
          text: 'Black',
          value: 'black',
        },
        {
          text: 'White',
          value: 'white',
        },
        {
          text: 'Custom',
          value: false,
        },
      ],
      rules: {
        customColor: (value) => {
          return (
            /^#(?:[0-9a-fA-F]{3}){1,2}$/.test(value) || this.customColorHint
          )
        },
      },
    }
  },
  computed: {
    saveObj: function () {
      return JSON.stringify({
        text: this.text,
        fontColor: this.selectedFontColor || this.customFontColor,
        backgroundColor:
          this.selectedBackgroundColor || this.customBackgroundColor,
      })
    },
    formValid: function () {
      return (
        (this.selectedFontColor ||
          this.rules.customColor(this.customFontColor) === true) &&
        (this.selectedBackgroundColor ||
          this.rules.customColor(this.customBackgroundColor) === true)
      )
    },
  },
  watch: {
    displayContextTag: function (val) {
      if (val) {
        this.text = 'REPLACEME'
      } else {
        this.text = null
      }
    },
    customFontColor: function (val) {
      if (val && val.length && !val.startsWith('#')) {
        this.customFontColor = `#${val}`
      }
    },
    customBackgroundColor: function (val) {
      if (val && val.length && !val.startsWith('#')) {
        this.customBackgroundColor = `#${val}`
      }
    },
  },
  created() {
    this.loadSetting(settingName)
  },
  methods: {
    save() {
      this.saveSetting(settingName, this.saveObj)
    },
    parseSetting: function (response) {
      if (response) {
        const parsed = JSON.parse(response)
        this.displayContextTag = !!parsed.text
        this.text = parsed.text
        if (parsed.backgroundColor) {
          const colorExists = this.colors.some(color => color.value === parsed.backgroundColor)
          if (colorExists) {
            this.selectedBackgroundColor = parsed.backgroundColor
          } else {
            this.customBackgroundColor = parsed.backgroundColor
            this.selectedBackgroundColor = false
          }
        }
        if (parsed.fontColor) {
          const colorExists = this.colors.some(color => color.value === parsed.fontColor)
          if (colorExists) {
            this.selectedFontColor = parsed.fontColor
          } else {
            this.customFontColor = parsed.fontColor
            this.selectedFontColor = false
          }
        }
      }
    },
  },
}
</script>
