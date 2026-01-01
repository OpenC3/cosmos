<!--
# Copyright 2026 OpenC3, Inc.
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
  <v-text-field
    v-model="inputValue"
    :label="label"
    :rules="computedRules"
    :hide-details="hideDetails"
    :variant="variant"
    :density="density"
    :style="computedStyle"
    :class="textFieldClass"
    :disabled="disabled"
    :data-test="dataTest"
    @blur="handleBlur"
    @keydown.enter="handleBlur"
  >
    <template #prepend-inner>
      <v-menu
        v-model="menu"
        :close-on-content-click="false"
        location="bottom start"
        transition="scale-transition"
      >
        <template #activator="{ props: menuProps }">
          <v-icon v-bind="menuProps" class="cursor-pointer">
            mdi-clock-outline
          </v-icon>
        </template>
        <v-card class="time-picker-card">
          <v-time-picker
            v-model="tempTime"
            :format="timeFormat"
            scrollable
            use-seconds
            hide-header
          />
          <v-card-actions>
            <v-spacer />
            <v-btn variant="text" @click="cancel">Cancel</v-btn>
            <v-btn color="primary" variant="text" @click="save">OK</v-btn>
          </v-card-actions>
        </v-card>
      </v-menu>
    </template>
  </v-text-field>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'

export default {
  inheritAttrs: false,
  props: {
    modelValue: {
      type: String,
      default: '',
    },
    label: {
      type: String,
      default: 'Time',
    },
    rules: {
      type: Array,
      default: () => [],
    },
    hideDetails: {
      type: [Boolean, String],
      default: false,
    },
    variant: {
      type: String,
      default: 'filled',
    },
    density: {
      type: String,
      default: 'default',
    },
    style: {
      type: [String, Object],
      default: '',
    },
    textFieldClass: {
      type: String,
      default: '',
    },
    dataTest: {
      type: String,
      default: '',
    },
    disabled: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      menu: false,
      timeFormat: 'ampm',
      tempTime: null,
      inputValue: '',
    }
  },
  computed: {
    computedStyle() {
      if (typeof this.style === 'string') {
        return this.style
      }
      return this.style
    },
    computedRules() {
      // Wrap the passed rules to validate against the 24-hour modelValue
      return this.rules.map((rule) => {
        return () => {
          return rule(this.modelValue)
        }
      })
    },
  },
  watch: {
    modelValue: {
      immediate: true,
      handler(newVal) {
        // Update input display when modelValue changes externally
        if (!this.menu) {
          this.inputValue = this.formatForDisplay(newVal)
        }
      },
    },
    menu(newVal) {
      if (newVal) {
        // When menu opens, initialize tempTime with current value
        this.tempTime = this.modelValue || '00:00:00'
      }
    },
  },
  async created() {
    await this.loadTimeFormat()
    // Update display after loading time format
    this.inputValue = this.formatForDisplay(this.modelValue)
  },
  methods: {
    async loadTimeFormat() {
      try {
        const api = new OpenC3Api()
        const response = await api.get_setting('time_format')
        if (response) {
          this.timeFormat = response
        }
      } catch (error) {
        // Default to 'ampm' if setting is not found
        this.timeFormat = 'ampm'
      }
    },
    formatForDisplay(time24) {
      if (!time24) return ''
      if (this.timeFormat === '24hr') {
        return time24
      }
      return this.convertTo12Hour(time24)
    },
    handleBlur() {
      // Parse input and update modelValue
      const parsed = this.parseTimeInput(this.inputValue)
      if (parsed) {
        this.$emit('update:modelValue', parsed)
        this.inputValue = this.formatForDisplay(parsed)
      } else if (this.inputValue === '') {
        this.$emit('update:modelValue', '')
      } else {
        // Invalid input, revert to current modelValue display
        this.inputValue = this.formatForDisplay(this.modelValue)
      }
    },
    parseTimeInput(input) {
      if (!input || input.trim() === '') return ''

      // Try to parse 24-hour format: HH:mm:ss or HH:mm
      const time24Match = input.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/)
      if (time24Match) {
        const hours = parseInt(time24Match[1], 10)
        const minutes = parseInt(time24Match[2], 10)
        const seconds = time24Match[3] ? parseInt(time24Match[3], 10) : 0
        if (
          hours >= 0 &&
          hours <= 23 &&
          minutes >= 0 &&
          minutes <= 59 &&
          seconds >= 0 &&
          seconds <= 59
        ) {
          return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
        }
      }

      // Try to parse 12-hour format: HH:mm:ss AM/PM or HH:mm AM/PM
      const time12Match = input.match(
        /^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM|am|pm)$/i,
      )
      if (time12Match) {
        let hours = parseInt(time12Match[1], 10)
        const minutes = parseInt(time12Match[2], 10)
        const seconds = time12Match[3] ? parseInt(time12Match[3], 10) : 0
        const period = time12Match[4].toUpperCase()

        if (
          hours >= 1 &&
          hours <= 12 &&
          minutes >= 0 &&
          minutes <= 59 &&
          seconds >= 0 &&
          seconds <= 59
        ) {
          // Convert to 24-hour format
          if (period === 'AM') {
            if (hours === 12) hours = 0
          } else {
            if (hours !== 12) hours += 12
          }
          return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
        }
      }

      return null // Invalid format
    },
    save() {
      this.$emit('update:modelValue', this.tempTime)
      this.inputValue = this.formatForDisplay(this.tempTime)
      this.menu = false
    },
    cancel() {
      this.tempTime = this.modelValue || '00:00:00'
      this.menu = false
    },
    convertTo12Hour(time24) {
      if (!time24) return ''
      const parts = time24.split(':')
      if (parts.length < 2) return time24
      let hours = parseInt(parts[0], 10)
      const minutes = parts[1]
      const seconds = parts.length > 2 ? parts[2] : '00'
      const ampm = hours >= 12 ? 'PM' : 'AM'
      hours = hours % 12
      hours = hours ? hours : 12 // 0 should be 12
      const paddedHours = hours.toString().padStart(2, '0')
      return `${paddedHours}:${minutes}:${seconds} ${ampm}`
    },
  },
}
</script>

<style scoped>
.time-picker-card {
  background-color: var(--color-background-surface-default);
}
.time-picker-card :deep(.v-time-picker) {
  background-color: var(--color-background-surface-default);
}
.time-picker-card :deep(.v-time-picker-clock__container) {
  background-color: var(--color-background-surface-default);
}
.time-picker-card :deep(.v-time-picker-clock) {
  background-color: var(--color-background-base-default);
}
.time-picker-card :deep(.v-picker__header) {
  background-color: var(--color-background-surface-header);
}
.time-picker-card :deep(.v-picker-title) {
  background-color: var(--color-background-surface-header);
}
.cursor-pointer {
  cursor: pointer;
}
</style>
