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
  <div ref="container" class="d-flex flex-row">
    <labelvalue-widget
      :parameters="labelValueParameters"
      :settings="settings"
    />
    <rangebar-widget :parameters="rangeBarParameters" />
  </div>
</template>

<script>
import LabelvalueWidget from './LabelvalueWidget.vue'
import RangebarWidget from './RangebarWidget.vue'
import Widget from './Widget'

export default {
  mixins: [Widget],
  components: {
    LabelvalueWidget,
    RangebarWidget,
  },
  computed: {
    labelValueParameters() {
      return [
        this.parameters[0],
        this.parameters[1],
        this.parameters[2],
        // Skip 3,4 which is range min,max
        this.parameters[5],
        this.parameters[6], // num characters
      ]
    },
    rangeBarParameters() {
      return [
        this.parameters[0],
        this.parameters[1],
        this.parameters[2],
        this.parameters[3],
        this.parameters[4],
        this.parameters[5],
        // Skip 6 which is num chars
        this.parameters[7],
        this.parameters[8],
      ]
    },
  },
}
</script>
