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
  <div
    v-show="isVisible"
    ref="rawDialog"
    :style="computedStyle"
    class="raw-dialog"
  >
    <div ref="bar" class="toolbar-wrapper">
      <v-toolbar height="24">
        <v-btn
          icon="mdi-content-copy"
          variant="text"
          density="compact"
          data-test="copy-icon"
          @click="copyRawData"
        />
        <v-btn
          icon="mdi-download"
          variant="text"
          density="compact"
          data-test="download"
          @click="downloadRawData"
        />
        <v-spacer />
        <span> {{ type }} </span>
        <v-spacer />
        <v-btn
          icon="mdi-close-box"
          variant="text"
          density="compact"
          data-test="close"
          @click="$emit('close')"
        />
      </v-toolbar>
    </div>
    <v-card>
      <v-card-title class="d-flex align-center justify-content-space-between">
        <span> {{ header }} </span>
        <v-spacer />
        <v-btn
          :icon="buttonIcon"
          variant="text"
          data-test="pause"
          @click="pause"
        />
      </v-card-title>
      <v-card-text>
        <v-row dense>
          <v-col cols="4">
            <span> Received Time: </span>
          </v-col>
          <v-col class="text-right">
            <span> {{ receivedTime }} </span>
          </v-col>
        </v-row>
        <v-row dense>
          <v-col cols="4">
            <span> Count: </span>
          </v-col>
          <v-col class="text-right">
            <span> {{ receivedCount }} </span>
          </v-col>
        </v-row>
        <raw-buffer v-model="rawData" @formatted="updateFormatted" />
      </v-card-text>
    </v-card>
  </div>
</template>

<script>
import { format } from 'date-fns'

import Updater from './Updater'
import RawBuffer from './RawBuffer.vue'

export default {
  components: {
    RawBuffer,
  },
  mixins: [Updater],
  props: {
    type: {
      type: String,
      required: true,
    },
    visible: Boolean,
    targetName: {
      type: String,
      required: true,
    },
    packetName: {
      type: String,
      required: true,
    },
    zIndex: {
      type: Number,
      default: 1,
    },
  },
  emits: ['close', 'display', 'focus'],
  data() {
    return {
      header: '',
      receivedTime: '',
      rawData: '',
      formattedData: '',
      paused: false,
      receivedCount: '',
      dragX: 0,
      dragY: 0,
      top: 0,
      left: 0,
    }
  },
  computed: {
    buttonIcon: function () {
      if (this.paused) {
        return 'mdi-play'
      } else {
        return 'mdi-pause'
      }
    },
    isVisible: {
      get: function () {
        return this.visible
      },
      // Reset all the data to defaults
      set: function (bool) {
        this.header = ''
        this.receivedTime = ''
        this.rawData = ''
        this.receivedCount = ''
        this.paused = false
        this.$emit('display', bool)
      },
    },
    computedStyle() {
      let style = {}
      style['top'] = this.top + 'px'
      style['left'] = this.left + 'px'
      style['z-index'] = this.zIndex
      return style
    },
  },
  mounted() {
    this.$refs.bar.onmousedown = this.dragMouseDown
    this.$refs.rawDialog.onmouseup = this.focusEvent
  },
  methods: {
    updateFormatted: function (formatted) {
      this.formattedData = formatted
    },
    focusEvent: function (e) {
      this.$emit('focus')
    },
    dragMouseDown: function (e) {
      e = e || window.event
      e.preventDefault()
      // get the mouse cursor position at startup:
      this.dragX = e.clientX
      this.dragY = e.clientY
      document.onmouseup = this.closeDragElement
      // call a function whenever the cursor moves:
      document.onmousemove = this.elementDrag
    },
    elementDrag: function (e) {
      e = e || window.event
      e.preventDefault()
      // calculate the new cursor position:
      let xOffset = this.dragX - e.clientX
      let yOffset = this.dragY - e.clientY
      this.dragX = e.clientX
      this.dragY = e.clientY
      // set the element's new position:
      this.top = this.$refs.bar.parentElement.offsetTop - yOffset
      this.left = this.$refs.bar.parentElement.offsetLeft - xOffset
    },
    closeDragElement: function () {
      // stop moving when mouse button is released
      document.onmouseup = null
      document.onmousemove = null

      // Prevent user from dropping it above the top of the app window
      this.top = Math.max(-47, this.top)
    },
    buildRawData: function () {
      return `${this.header}\nReceived Time: ${this.receivedTime}\nCount: ${this.receivedCount}\n${this.formattedData}`
    },
    copyRawData: function () {
      navigator.clipboard.writeText(this.buildRawData())
    },
    downloadRawData: function () {
      const blob = new Blob([this.buildRawData()], {
        type: 'plain/text',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      const dt = format(Date.now(), 'yyyy_MM_dd_HH_mm_ss')
      link.setAttribute(
        'download',
        `${dt}_${this.targetName}_${this.packetName}.txt`,
      )
      link.click()
    },
    pause: function () {
      this.paused = !this.paused
    },
    update: function () {
      if (!this.isVisible || this.paused) return
      this.header = `Raw ${this.type} Packet: ${this.targetName} ${this.packetName}`

      if (this.type === 'Telemetry') {
        this.updateTelemetry()
      } else {
        this.updateCommand()
      }
    },
    updateTelemetry: function () {
      this.api
        .get_tlm_buffer(this.targetName, this.packetName)
        .then((result) => {
          this.receivedTime = new Date(result.time / 1000000)
          this.receivedCount = result.received_count
          this.rawData = result.buffer
        })
    },
    updateCommand: function () {
      this.api
        .get_cmd_buffer(this.targetName, this.packetName)
        .then((result) => {
          this.receivedTime = new Date(result.time / 1000000)
          this.receivedCount = result.received_count
          this.rawData = result.buffer
        })
    },
  },
}
</script>
<style scoped>
.raw-dialog {
  position: absolute;
  top: 0px;
  left: 5px;
  z-index: 1;
  border: solid;
  border-width: 1px;
  border-color: white;
  resize: vertical;
  overflow: auto;
  min-height: 28px;
  max-height: 85vh;
  width: 815px;
  background-color: var(--color-background-base-selected);
}

.raw-dialog .toolbar-wrapper {
  position: sticky;
  top: 0;
  z-index: 1;
}

.raw-dialog :deep(.v-card-text) {
  background-color: var(--color-background-base-selected);
}

.v-textarea :deep(textarea) {
  margin-top: 10px;
  font-family: 'Courier New', Courier, monospace;
  overflow-y: hidden;
}
</style>
