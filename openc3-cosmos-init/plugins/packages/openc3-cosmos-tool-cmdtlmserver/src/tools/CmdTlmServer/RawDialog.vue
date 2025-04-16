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
          data-test="copy-icon"
          @click="copyRawData"
        />
        <v-btn
          icon="mdi-download"
          variant="text"
          data-test="download"
          @click="downloadRawData"
        />
        <v-spacer />
        <span> {{ type }} </span>
        <v-spacer />
        <v-btn
          icon="mdi-close-box"
          variant="text"
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
        <v-textarea
          v-model="rawData"
          class="pa-0 ma-0"
          :rows="numRows"
          no-resize
          readonly
        />
      </v-card-text>
    </v-card>
  </div>
</template>

<script>
import { format } from 'date-fns'

import Updater from './Updater'

export default {
  mixins: [Updater],
  props: {
    type: String,
    visible: Boolean,
    targetName: String,
    packetName: String,
    zIndex: {
      type: Number,
      default: 1,
    },
  },
  data() {
    return {
      header: '',
      receivedTime: '',
      rawData: '',
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
    numRows() {
      // This is because v-textarea doesn't behave correctly with really long monospace text
      let lines = this.rawData.split('\n').length
      // Add a small fudge factor every 2000 lines to prevent clipping at the bottom
      return lines + Math.floor(lines / 2000)
    },
  },
  mounted() {
    this.$refs.bar.onmousedown = this.dragMouseDown
    this.$refs.rawDialog.onmouseup = this.focusEvent
  },
  methods: {
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
    },
    buildRawData: function () {
      return `${this.header}\nReceived Time: ${this.receivedTime}\nCount: ${this.receivedCount}\n${this.rawData}`
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
          let buffer_data = result.buffer
          if (buffer_data.raw !== undefined) {
            buffer_data = buffer_data.raw
          } else {
            let utf8Encode = new TextEncoder()
            buffer_data = utf8Encode.encode(buffer_data)
          }
          this.receivedTime = new Date(result.time / 1000000)
          this.receivedCount = result.received_count
          this.rawData =
            'Address   Data                                             Ascii\n' +
            '---------------------------------------------------------------------------\n' +
            this.formatBuffer(buffer_data)
        })
    },
    updateCommand: function () {
      this.api
        .get_cmd_buffer(this.targetName, this.packetName)
        .then((result) => {
          let buffer_data = result.buffer
          if (buffer_data.raw !== undefined) {
            buffer_data = buffer_data.raw
          } else {
            let utf8Encode = new TextEncoder()
            buffer_data = utf8Encode.encode(buffer_data)
          }
          this.receivedTime = new Date(result.time / 1000000)
          this.receivedCount = result.received_count
          this.rawData =
            'Address   Data                                             Ascii\n' +
            '---------------------------------------------------------------------------\n' +
            this.formatBuffer(buffer_data)
        })
    },
    // TODO: Perhaps move this to a utility library
    formatBuffer: function (buffer) {
      let string = ''
      let index = 0
      let ascii = ''
      buffer.forEach((byte) => {
        if (index % 16 === 0) {
          string += this.numHex(index, 8) + ': '
        }
        string += this.numHex(byte)

        // Create the ASCII representation if printable
        if (byte >= 32 && byte <= 126) {
          ascii += String.fromCharCode(byte)
        } else {
          ascii += ' '
        }

        index++

        if (index % 16 === 0) {
          string += '  ' + ascii + '\n'
          ascii = ''
        } else {
          string += ' '
        }
      })

      // We're done printing all the bytes. Now check to see if we ended in the
      // middle of a line. If so we have to print out the final ASCII if
      // requested.
      if (index % 16 != 0) {
        let existing_length = (index % 16) - 1 + (index % 16) * 2
        // 47 is (16 * 2) + 15 separator spaces
        let filler = ' '.repeat(47 - existing_length)
        let ascii_filler = ' '.repeat(16 - ascii.length)
        string += filler + '  ' + ascii + ascii_filler
      }
      return string
    },
    numHex(num, width = 2) {
      let hex = num.toString(16)
      return '0'.repeat(width - hex.length) + hex
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
