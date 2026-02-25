<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div ref="container" class="d-flex flex-row" :style="computedStyle">
    <labelvalue-widget
      v-bind="$attrs"
      :parameters="parameters"
      :settings="labelValueSettings"
      :screen-values="screenValues"
      :screen-time-zone="screenTimeZone"
    />
    <limitsbar-widget
      v-bind="$attrs"
      :parameters="parameters"
      :settings="[...appliedSettings]"
      :screen-values="screenValues"
      :widget-index="2"
      :line="line"
      :line-number="lineNumber"
    />
  </div>
</template>

<script>
import LabelvalueWidget from './LabelvalueWidget.vue'
import LimitsbarWidget from './LimitsbarWidget.vue'
import Widget from './Widget'

export default {
  components: {
    LabelvalueWidget,
    LimitsbarWidget,
  },
  mixins: [Widget],
  computed: {
    // Filter the settings to just the ones that apply to LABELVALUE.
    // Normally this is automatically handled by Widget.js computedStyle().
    // However, if someone (like LimitsControl) tries to set an overall
    // WIDTH of the LABELVALUELIMITSBAR, without filtering it will get
    // passed down to LABELVALUE and be set there as well.
    labelValueSettings() {
      return [
        // Get the screen setting
        ...this.appliedSettings.filter((x) => x[0] === '__SCREEN_ID__'),
        // Get all the setting that apply to labelvalue (0, 1 widgets)
        ...this.settings.filter(
          (x) => Number.parseInt(x[0]) === 0 || Number.parseInt(x[0]) === 1,
        ),
      ]
    },
  },
}
</script>
