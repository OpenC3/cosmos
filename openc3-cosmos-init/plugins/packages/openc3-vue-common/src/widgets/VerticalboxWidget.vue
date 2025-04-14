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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <label-widget
      v-if="parameters.length > 0"
      :parameters="parameters.slice(0, 1)"
      :settings="[...labelSettings]"
      :widget-index="0"
    />
    <horizontal-line-widget
      :settings="[...appliedSettings]"
      :widget-index="1"
    />
    <vertical-widget
      v-bind="listeners"
      :parameters="parameters.slice(1)"
      :settings="settings"
      :widgets="widgets"
      :screen-values="screenValues"
      :screen-time-zone="screenTimeZone"
    />
  </div>
</template>

<script>
import LabelWidget from './LabelWidget.vue'
import HorizontalLineWidget from './HorizontallineWidget.vue'
import VerticalWidget from './VerticalWidget.vue'
import Layout from './Layout'

export default {
  components: {
    LabelWidget,
    HorizontalLineWidget,
    VerticalWidget,
  },
  mixins: [Layout],
  created() {
    this.labelSettings = [...this.appliedSettings]
    // Set the font-weight to bold if not already set
    const fontWeightSetting = this.labelSettings.find(
      (setting) =>
        setting[0] === '0' &&
        setting[1] === 'RAW' &&
        setting[2] === 'font-weight',
    )
    if (!fontWeightSetting) {
      this.labelSettings.push(['0', 'RAW', 'font-weight', 'bold'])
    }
  },
}
</script>
