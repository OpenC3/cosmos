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
  <div ref="container" class="d-flex flex-column" :style="computedStyle">
    <component
      v-bind="$attrs"
      v-for="(widget, index) in widgets"
      :key="index"
      :is="widget.type"
      :target="widget.target"
      :parameters="widget.parameters"
      :settings="widget.appliedSettings"
      :screenValues="widget.screenValues"
      :screenTimeZone="widget.screenTimeZone"
      :widgets="widget.widgets"
      :name="widget.name"
      :line="widget.line"
      :line-number="widget.lineNumber"
    />
  </div>
</template>

<script>
import Layout from './Layout'
export default {
  mixins: [Layout],
  created: function () {
    if (this.parameters[0]) {
      let margin = this.parameters[0]
      this.widgets.forEach((widget) => {
        // Don't push MARGIN on a widget that's already defined it
        const found = widget.settings.find(
          (setting) =>
            setting[0] === 'MARGIN' ||
            (setting[0] === 'RAW' &&
              setting[1].toUpperCase().includes('MARGIN')),
        )
        if (found === undefined) {
          widget.settings.push(['MARGIN', margin])
        }
      })
    }
  },
}
</script>
