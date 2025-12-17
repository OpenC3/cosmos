<!--
# Copyright 2025, OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-tabs v-model="mode" class="ml-3">
    <v-tab value="binary"> Binary/Ascii </v-tab>
    <v-tab value="utf8"> UTF-8 </v-tab>
  </v-tabs>
  <v-textarea
    ref="myText"
    v-model="formattedData"
    class="pa-0 ma-0"
    :rows="numRows"
    no-resize
    readonly
  />
</template>

<script>
import { format } from 'date-fns'

export default {
  props: {
    modelValue: {
      type: Object,
      default: null,
    },
  },
  emits: ['formatted'],
  data() {
    return {
      mode: 'binary',
      textWidth: null,
      bytesPerLine: 16,
    }
  },
  computed: {
    numRows() {
      // This is because v-textarea doesn't behave correctly with really long monospace text
      let lines = this.formattedData.split('\n').length
      // Add a small fudge factor every 2000 lines to prevent clipping at the bottom
      return lines + Math.floor(lines / 2000)
    },
    formattedData() {
      if (this.textWidth) {
        this.bytesPerLine = 16
        if (this.textWidth <= 450) {
          this.bytesPerLine = 4
        } else if (this.textWidth <= 770) {
          this.bytesPerLine = 8
        }

        let data = ''
        if (this.mode === 'binary') {
          data =
            'Address   Data  ' + '   '.repeat(this.bytesPerLine - 2) + ' Ascii\n' +
            '----------' + '---'.repeat(this.bytesPerLine) + '-'.repeat(this.bytesPerLine) + '-\n'
        }
        data = data + this.formatBuffer(this.modelValue)
        this.$emit('formatted', data)
        return data
      } else {
        return ''
      }
    },
  },
  mounted() {
    this.textWidth = this.$refs.myText.clientWidth
  },
  methods: {
    formatBuffer: function (buffer) {
      if (buffer === null || buffer.length === 0) {
        return 'No Data'
      }

      // buffer will either be a String or an object with
      // a raw field
      if (buffer.raw !== undefined) {
        buffer = buffer.raw
      } else {
        let utf8Encode = new TextEncoder()
        buffer = utf8Encode.encode(buffer)
      }

      if (this.mode === 'utf8') {
        let bytesView = new Uint8Array(buffer)
        return new TextDecoder().decode(bytesView)
      } else {
        if (buffer === null) {return 'No Data'}
        let string = ''
        let index = 0
        let ascii = ''
        buffer.forEach((byte) => {
          if (index % this.bytesPerLine === 0) {
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

          if (index % this.bytesPerLine === 0) {
            string += '  ' + ascii + '\n'
            ascii = ''
          } else {
            string += ' '
          }
        })

        // We're done printing all the bytes. Now check to see if we ended in the
        // middle of a line. If so we have to print out the final ASCII if
        // requested.
        if (index % this.bytesPerLine != 0) {
          string += '   '.repeat(this.bytesPerLine - (index % this.bytesPerLine)) + ' ' + ascii
        }
        return string
      }
    },
    numHex(num, width = 2) {
      let hex = num.toString(16)
      return '0'.repeat(width - hex.length) + hex
    },
  },
}
</script>
<style scoped>
.v-textarea :deep(textarea) {
  margin-top: 10px;
  font-family: 'Courier New', Courier, monospace;
  overflow-y: hidden;
}
</style>
