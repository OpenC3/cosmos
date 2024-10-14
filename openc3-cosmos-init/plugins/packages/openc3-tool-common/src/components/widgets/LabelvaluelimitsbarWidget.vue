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
  <div ref="container" class="d-flex flex-row" :style="computedStyle">
    <labelvalue-widget
      v-bind="$attrs"
      :parameters="parameters"
      :settings="labelValueSettings"
      :screen-values="screenValues"
      :screen-time-zone="screenTimeZone"
    />
    <limitsbar-widget
      class="pt-1"
      v-bind="$attrs"
      :parameters="parameters"
      :settings="[...settings]"
      :screen-values="screenValues"
      :widget-index="2"
    />
  </div>
</template>

<script>
import LabelvalueWidget from './LabelvalueWidget.vue'
import LimitsbarWidget from './LimitsbarWidget.vue'
import Widget from './Widget'

export default {
  mixins: [Widget],
  components: {
    LabelvalueWidget,
    LimitsbarWidget,
  },
  computed: {
    // Filter the settings to just the ones that apply to LABELVALUE.
    // Normally this is automatically handled by Widget.js computedStyle().
    // However, if someone (like LimitsControl) tries to set an overall
    // WIDTH of the LABELVALUELIMITSBAR, without filtering it will get
    // passed down to LABELVALUE and be set there as well.
    labelValueSettings() {
      return [
        // Get all the setting that apply to labelvalue (0, 1 widgets)
        ...this.settings.filter(
          (x) => parseInt(x[0]) === 0 || parseInt(x[0]) === 1,
        ),
      ]
    },
  },
}
</script>
