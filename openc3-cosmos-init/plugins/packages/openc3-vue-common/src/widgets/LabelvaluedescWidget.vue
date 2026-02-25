<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div ref="container" class="d-flex flex-row" :style="computedStyle">
    <label-widget
      :parameters="labelName"
      :settings="[...settings]"
      :line="line"
      :line-number="lineNumber"
      :widget-index="0"
    />
    <value-widget
      v-bind="$attrs"
      :parameters="valueParameters"
      :settings="[...settings]"
      :screen-values="screenValues"
      :screen-time-zone="screenTimeZone"
      :line="line"
      :line-number="lineNumber"
      :widget-index="1"
    />
  </div>
</template>

<script>
import Widget from './Widget'
import LabelWidget from './LabelWidget.vue'
import ValueWidget from './ValueWidget.vue'
import { OpenC3Api } from '@openc3/js-common/services'

export default {
  components: {
    LabelWidget,
    ValueWidget,
  },
  mixins: [Widget],
  data() {
    return {
      description: '',
      valueParameters: [],
    }
  },
  computed: {
    labelName() {
      return [this.description]
    },
  },
  created() {
    this.valueParameters = this.parameters.slice(0, 3)
    if (this.parameters[4] != undefined) {
      this.valueParameters.push(this.parameters[4])
    }
    if (this.parameters[5] != undefined) {
      this.valueParameters.push(this.parameters[5])
    }
    if (this.parameters.length > 3) {
      this.description = this.parameters[3]
    } else {
      new OpenC3Api()
        .get_item(this.parameters[0], this.parameters[1], this.parameters[2])
        .then((details) => {
          this.description = details['description']
        })
    }
  },
}
</script>
