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
  <div class="textbox-widget-container">
    <v-textarea
      solo
      dense
      readonly
      hide-details
      placeholder="Value"
      :height="height"
      :value="_value"
      :class="valueClass"
      :style="[computedStyle, aging]"
      data-test="valueText"
      @contextmenu="showContextMenu"
    />
    <v-menu
      v-model="contextMenuShown"
      :position-x="x"
      :position-y="y"
      absolute
      offset-y
    >
      <v-list>
        <v-list-item
          v-for="(item, index) in contextMenuOptions"
          :key="index"
          @click.stop="item.action"
        >
          <v-list-item-title>{{ item.title }}</v-list-item-title>
        </v-list-item>
      </v-list>
    </v-menu>

    <details-dialog
      :target-name="parameters[0]"
      :packet-name="parameters[1]"
      :item-name="parameters[2]"
      v-model="viewDetails"
    />
  </div>
</template>

<script>
import VWidget from './VWidget'
import WidthSetter from './WidthSetter'
import DetailsDialog from '../../components/DetailsDialog'
import 'sprintf-js'

export default {
  components: {
    DetailsDialog,
  },
  data: function () {
    return {
      height: 100,
    }
  },
  mixins: [VWidget, WidthSetter],
  computed: {
    aging() {
      return {
        '--aging': this.grayLevel,
      }
    },
  },
  created: function () {
    if (this.parameters[3]) {
      this.width = parseInt(this.parameters[3])
    }
    if (this.parameters[4]) {
      this.height = parseInt(this.parameters[4])
    }
  },
  methods: {
    getType: function () {
      var type = 'CONVERTED'
      if (this.parameters[5]) {
        type = this.parameters[5]
      }
      return type
    },
  },
}
</script>

<style scoped>
.textbox-widget-container :deep(.v-input__slot) {
  background: rgba(var(--aging), var(--aging), var(--aging), 1) !important;
}
.value :deep(div) {
  min-height: 24px !important;
  display: flex !important;
  align-items: center !important;
}
.openc3-green :deep(input) {
  color: rgb(0, 200, 0);
}
.openc3-yellow :deep(input) {
  color: rgb(255, 220, 0);
}
.openc3-red :deep(input) {
  color: rgb(255, 45, 45);
}
.openc3-blue :deep(input) {
  color: rgb(0, 153, 255);
}
.openc3-purple :deep(input) {
  color: rgb(200, 0, 200);
}
.openc3-black :deep(input) {
  color: black;
}
.openc3-white :deep(input) {
  color: white;
}
</style>
