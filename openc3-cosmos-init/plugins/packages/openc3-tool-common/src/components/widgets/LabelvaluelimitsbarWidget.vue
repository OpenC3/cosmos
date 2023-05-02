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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div ref="container" class="d-flex flex-row" :style="computedStyle">
    <labelvalue-widget
      :parameters="parameters"
      :settings="labelValueSettings"
    />
    <limitsbar-widget
      :parameters="limitsBarParameters"
      :settings="[...settings]"
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
        // Get the screen setting
        ...this.settings.filter((x) => x[0] === '__SCREEN__'),
        // Get all the setting that apply to labelvalue (0, 1 widgets)
        ...this.settings.filter(
          (x) => parseInt(x[0]) === 0 || parseInt(x[0]) === 1
        ),
      ]
    },
    limitsBarParameters() {
      return [
        this.parameters[0],
        this.parameters[1],
        this.parameters[2],
        // Always pass CONVERTED to the LimitsBar so it calculate the limits location
        'CONVERTED',
      ]
    },
  },
}
</script>
