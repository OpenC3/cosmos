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
  <table :style="computedStyle" role="presentation">
    <tr v-for="(chunk, rindex) in widgetChunks" :key="'r' + rindex">
      <td v-for="(widget, cindex) in chunk" :key="'c' + cindex">
        <component
          v-bind="listeners"
          :is="widget.type"
          :target="widget.target"
          :parameters="widget.parameters"
          :settings="widget.settings"
          :screen-values="screenValues"
          :screen-time-zone="screenTimeZone"
          :widgets="widget.widgets"
          :name="widget.name"
          :line="widget.line"
          :line-number="widget.lineNumber"
        />
      </td>
    </tr>
  </table>
</template>

<script>
import Layout from './Layout'
import _ from 'lodash'
export default {
  mixins: [Layout],
  computed: {
    columns() {
      return parseInt(this.parameters[0])
    },
    widgetChunks() {
      return _.chunk(this.widgets, this.columns)
    },
  },
  created: function () {
    if (this.parameters[1]) {
      let margin = this.parameters[1]
      this.widgets.forEach((widget) => {
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
