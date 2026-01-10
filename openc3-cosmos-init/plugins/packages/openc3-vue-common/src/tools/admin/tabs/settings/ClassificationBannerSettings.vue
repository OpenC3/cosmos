<!--
# Copyright 2024 OpenC3, Inc.
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
    <v-card-title>Classification Banner Settings</v-card-title>
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
            v-model="text"
            label="Text"
            data-test="classification-banner-text"
          />
        </v-col>
      </v-row>
      <v-row dense>
        <v-col>
          <v-select
            v-model="selectedBackgroundColor"
            label="Background color"
            :items="colors"
            item-title="text"
            data-test="classification-banner-background-color"
          >
            <template v-if="selectedBackgroundColor" #prepend-inner>
              <v-icon :color="selectedBackgroundColor"> mdi-square </v-icon>
            </template>
            <template #item="{ props, item }">
              <v-list-item v-bind="props" :value="item.text">
                <template #prepend>
                  <v-icon v-if="item.value" :color="item.value">
                    mdi-square
                  </v-icon>
                </template>
              </v-list-item>
            </template>
          </v-select>
        </v-col>
        <v-col>
          <v-text-field
            v-model="customBackgroundColor"
            label="Custom background color"
            :hint="customColorHint"
            :disabled="selectedBackgroundColor !== false"
            :rules="[rules.customColor]"
            data-test="classification-banner-custom-background-color"
          >
            <template #prepend-inner>
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
            v-model="selectedFontColor"
            label="Font color"
            :items="colors"
            item-title="text"
            data-test="classification-banner-font-color"
          >
            <template v-if="selectedFontColor" #prepend-inner>
              <v-icon v-show="selectedFontColor" :color="selectedFontColor">
                mdi-square
              </v-icon>
            </template>
            <template #item="{ props, item }">
              <v-list-item v-bind="props" :value="item.text">
                <template #prepend>
                  <v-icon v-if="item.value" :color="item.value">
                    mdi-square
                  </v-icon>
                </template>
              </v-list-item>
            </template>
          </v-select>
        </v-col>
        <v-col>
          <v-text-field
            v-model="customFontColor"
            label="Custom font color"
            :hint="customColorHint"
            :disabled="selectedFontColor !== false"
            :rules="[rules.customColor]"
            data-test="classification-banner-custom-font-color"
          >
            <template #prepend-inner>
              <v-icon v-show="!selectedFontColor" :color="customFontColor">
                mdi-square
              </v-icon>
            </template>
          </v-text-field>
        </v-col>
      </v-row>
      <v-row dense>
        <v-col>
          <v-switch
            v-model="displayTopBanner"
            label="Display top banner"
            color="primary"
            data-test="display-top-banner"
          />
        </v-col>
        <v-col>
          <v-text-field
            v-model="topHeight"
            label="Top height"
            :disabled="!displayTopBanner"
            type="number"
            suffix="px"
            data-test="classification-banner-top-height"
          />
        </v-col>
        <v-col>
          <v-switch
            v-model="displayBottomBanner"
            label="Display bottom banner"
            color="primary"
            data-test="display-bottom-banner"
          />
        </v-col>
        <v-col>
          <v-text-field
            v-model="bottomHeight"
            label="Bottom height"
            :disabled="!displayBottomBanner"
            type="number"
            suffix="px"
            data-test="classification-banner-bottom-height"
          />
        </v-col>
      </v-row>
    </v-card-text>
    <v-card-actions>
      <v-btn
        :disabled="!formValid"
        color="success"
        variant="text"
        data-test="save-classification-banner"
        @click="save"
      >
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import Settings from './settings.js'

const settingName = 'classification_banner'
export default {
  mixins: [Settings],
  data() {
    return {
      text: '',
      displayTopBanner: false,
      displayBottomBanner: false,
      topHeight: 0,
      bottomHeight: 0,
      selectedBackgroundColor: 'red',
      customBackgroundColor: '',
      selectedFontColor: 'white',
      customFontColor: '',
      customColorHint: 'Enter a 3 or 6-digit hex color code',
      colors: [
        {
          text: 'Yellow',
          value: 'yellow',
        },
        {
          text: 'Orange',
          value: 'orange',
        },
        {
          text: 'Red',
          value: 'red',
        },
        {
          text: 'Purple',
          value: 'purple',
        },
        {
          text: 'Blue',
          value: 'blue',
        },
        {
          text: 'Green',
          value: 'green',
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
        topHeight: this.displayTopBanner ? this.topHeight : 0,
        bottomHeight: this.displayBottomBanner ? this.bottomHeight : 0,
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
    displayTopBanner: function (val) {
      if (val) {
        this.topHeight = 20
      } else {
        this.topHeight = 0
      }
    },
    displayBottomBanner: function (val) {
      if (val) {
        this.bottomHeight = 20
      } else {
        this.bottomHeight = 0
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
        this.text = parsed.text
        this.topHeight = parsed.topHeight
        this.bottomHeight = parsed.bottomHeight
        this.displayTopBanner = parsed.topHeight !== 0
        this.displayBottomBanner = parsed.bottomHeight !== 0
        if (parsed.backgroundColor && parsed.backgroundColor.startsWith('#')) {
          this.customBackgroundColor = parsed.backgroundColor
          this.selectedBackgroundColor = false
        } else {
          this.selectedBackgroundColor = parsed.backgroundColor
        }
        if (parsed.fontColor && parsed.fontColor.startsWith('#')) {
          this.customFontColor = parsed.fontColor
          this.selectedFontColor = false
        } else {
          this.selectedFontColor = parsed.fontColor
        }
      }
    },
  },
}
</script>
