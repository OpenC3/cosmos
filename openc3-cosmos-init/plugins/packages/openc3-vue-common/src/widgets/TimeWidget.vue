<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <OpenC3TimePicker
    v-model="timeValue"
    :label="label"
    :style="computedStyle"
    hide-details
  />
</template>

<script>
import Widget from './Widget'
import OpenC3TimePicker from '@/components/OpenC3TimePicker.vue'
import { TimeFilters } from '@/util'

export default {
  components: {
    OpenC3TimePicker,
  },
  mixins: [Widget, TimeFilters],
  data() {
    return {
      label: 'Time',
      timeValue: '',
    }
  },
  created() {
    if (this.parameters[0]) {
      this.label = this.parameters[0]
    }
    this.timeValue = this.formatTimeHMS(new Date(), this.screenTimeZone)
  },
  methods: {
    text() {
      return this.timeValue
    },
    time() {
      return this.timeValue
    },
  },
}
</script>
