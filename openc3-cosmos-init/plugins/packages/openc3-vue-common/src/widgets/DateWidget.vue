<!--
# Copyright 2024 OpenC3, Inc.
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
  <v-text-field
    v-model="dateValue"
    :label="label"
    :style="computedStyle"
    type="date"
    hide-details
  />
</template>

<script>
import Widget from './Widget'
import { TimeFilters } from '@/util'

export default {
  mixins: [Widget, TimeFilters],
  data() {
    return {
      label: 'Date',
      dateValue: '',
    }
  },
  created() {
    if (this.parameters[0]) {
      this.label = this.parameters[0]
    }
    this.dateValue = this.formatDate(new Date(), this.screenTimeZone)
  },
  methods: {
    text() {
      return this.dateValue
    },
    date() {
      return this.dateValue
    },
  },
}
</script>
