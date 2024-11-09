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
  <v-text-field
    v-model="timeValue"
    :label="label"
    :style="computedStyle"
    type="time"
    hide-details
  />
</template>

<script>
import Widget from './Widget'
import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters.js'

export default {
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
    this.timeValue = this.formatTimeHMS(new Date(), this.screen.timeZone)
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
