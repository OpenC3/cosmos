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
  <div class="array-widget-container">
    <v-textarea
      variant="solo"
      density="compact"
      readonly
      no-resize
      auto-grow
      rows="2"
      hide-details
      :model-value="_value"
      :class="valueClass"
      :style="[computedStyle, aging]"
      data-test="array-widget"
      @contextmenu="showContextMenu"
    />
    <v-menu v-model="contextMenuShown" :target="[x, y]">
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
import { DetailsDialog } from '@/components'
import VWidget from './VWidget'
import 'sprintf-js'

export default {
  components: {
    DetailsDialog,
  },
  data: function () {
    return {
      width: 200,
      height: 100,
      itemsPerRow: 4,
      formatter: null,
    }
  },
  mixins: [VWidget],
  computed: {
    aging() {
      return {
        '--aging': this.grayLevel,
      }
    },
  },
  created: function () {
    this.width = this.setWidth(this.parameters[3], 'px', this.width)
    this.height = this.setHeight(this.parameters[4], 'px', this.height)
    if (this.parameters[5]) {
      this.formatter = this.parameters[5]
    }
    if (this.parameters[6]) {
      this.itemsPerRow = parseInt(this.parameters[6])
    }
  },
  methods: {
    getType: function () {
      let type = 'CONVERTED'
      if (this.parameters[7]) {
        type = this.parameters[7]
      }
      return type
    },
    formatValue: function (data) {
      let text = ''
      let space = ' '
      let newLine = '\n'
      let count = 0

      if (Array.isArray(data)) {
        for (const value of data) {
          if (this.formatter && this.formatter?.toLowerCase() !== 'nil') {
            text += sprintf(this.formatter, value)
          } else {
            text += value
          }
          count += 1
          if (count % this.itemsPerRow === 0) {
            count = 0
            text += newLine
          } else {
            text += space
          }
        }
        return text.trim()
      } else {
        return data
      }
    },
  },
}
</script>

<style scoped>
.array-widget-container :deep(.v-input__slot) {
  background: rgba(var(--aging), var(--aging), var(--aging), 1) !important;
}
.value :deep(div) {
  min-height: 24px !important;
  display: flex !important;
  align-items: center !important;
}
.array-widget-container :deep(.v-field__loader) {
  display: none !important;
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
