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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div class="pa-2">
    <v-row dense class="mb-2">
      <v-col cols="4">
        <v-text-field
          v-model="filterText"
          label="Search"
          class="search"
          prepend-inner-icon="mdi-magnify"
          clearable
          variant="outlined"
          density="compact"
          single-line
          hide-details
          data-test="history-component-search"
        />
      </v-col>
      <v-col cols="8" class="mt-1">
        <v-slider
          v-model="pauseOffset"
          v-on:mousedown="pause"
          @click:prepend="stepBackward"
          @click:append="stepForward"
          prepend-icon="mdi-step-backward"
          append-icon="mdi-step-forward"
          :min="1 - currentConfig.history"
          :max="0"
          hide-details
        />
      </v-col>
    </v-row>
    <v-row dense no-gutters>
      <v-col>
        <div class="text-area-container">
          <!-- Note: Can't use auto-grow because we're constantly updating it
               and it causes issues with the scrollbar. Therefore we use rows
               and calculate the number of rows based on the displayText. -->
          <v-textarea
            ref="textarea"
            :model-value="displayText"
            :rows="rows"
            no-resize
            readonly
            variant="solo"
            flat
            hide-details
            data-test="history-component-text-area"
          />
          <div class="floating-buttons">
            <v-menu :close-on-content-click="false" :min-width="700">
              <template v-slot:activator="{ props }">
                <v-btn
                  class="ml-2"
                  color="secondary"
                  v-bind="props"
                  icon
                  size="small"
                  data-test="history-component-open-settings"
                >
                  <v-icon>astro:settings</v-icon>
                </v-btn>
              </template>
              <v-card>
                <v-card-title data-test="display-settings-card">
                  Display settings
                </v-card-title>
                <v-card-text>
                  <v-row>
                    <v-col>
                      <v-switch
                        v-model="currentConfig.showTimestamp"
                        label="Show timestamp"
                        density="compact"
                        hide-details
                        data-test="history-component-settings-show-timestamp"
                      />
                      <v-switch
                        v-if="hasRaw"
                        v-model="currentConfig.showAscii"
                        label="Show ASCII"
                        density="compact"
                        hide-details
                        data-test="history-component-settings-show-ascii"
                      />
                      <v-switch
                        v-if="hasRaw"
                        v-model="currentConfig.showLineAddress"
                        label="Show line address"
                        density="compact"
                        hide-details
                        data-test="history-component-settings-show-address"
                      />
                    </v-col>
                    <v-col>
                      <v-radio-group
                        v-model="currentConfig.newestAtTop"
                        label="Print newest packets to the"
                      >
                        <v-radio
                          label="Top"
                          :value="true"
                          data-test="history-component-settings-newest-top"
                        />
                        <v-radio
                          label="Bottom"
                          :value="false"
                          data-test="history-component-settings-newest-bottom"
                        />
                      </v-radio-group>
                    </v-col>
                    <v-col>
                      <v-text-field
                        v-model="currentConfig.history"
                        label="History Buffer"
                        type="number"
                        min="1"
                        persistent-hint
                        :rules="[rules.required, rules.min]"
                        data-test="history-component-settings-history"
                      />
                      <v-text-field
                        v-if="hasRaw"
                        v-model="currentConfig.bytesPerLine"
                        label="Bytes per line"
                        type="number"
                        min="1"
                        :rules="[rules.required, rules.min]"
                        data-test="history-component-settings-num-bytes"
                      />
                      <v-text-field
                        v-model="currentConfig.packetsToShow"
                        label="Packets to show"
                        type="number"
                        min="1"
                        :hint="`Maximum: ${currentConfig.history}`"
                        persistent-hint
                        :rules="[rules.required, rules.min, rules.max]"
                        data-test="history-component-settings-num-packets"
                      />
                    </v-col>
                  </v-row>
                </v-card-text>
              </v-card>
            </v-menu>
            <v-btn
              class="ml-2"
              v-on:click="download"
              color="secondary"
              icon
              size="small"
              data-test="history-component-download"
            >
              <v-icon>mdi-file-download</v-icon>
            </v-btn>
            <v-btn
              class="ml-2"
              :class="{ pulse: paused }"
              v-on:click="togglePlayPause"
              color="primary"
              icon
              data-test="history-component-play-pause"
            >
              <v-icon size="large" v-if="paused">mdi-play</v-icon>
              <v-icon size="large" v-else>mdi-pause</v-icon>
            </v-btn>
          </div>
        </div>
      </v-col>
    </v-row>
  </div>
</template>

<script>
import _ from 'lodash'
import { format } from 'date-fns'
import Component from './Component'

export default {
  props: ['calculatePacketText'],
  mixins: [Component],
  data: function () {
    return {
      history: [],
      historyPointer: -1, // index of the newest packet in history
      filterText: null,
      paused: false,
      pausedAt: 0,
      pauseOffset: 0,
      pausedHistory: [],
      rows: 1,
      textarea: null,
      displayText: '',
      rules: {
        required: (value) => !!value || 'Required.',
        min: (value) => value >= 1 || 'Minimum: 1',
        max: (value) =>
          parseInt(value) <= this.currentConfig.history ||
          `Maximum: ${this.currentConfig.history}`,
      },
    }
  },
  computed: {
    // These are just here to trigger their respective watch functions above
    // There's a better solution to this in Vue 3 v3.vuejs.org/api/computed-watch-api.html#watching-multiple-sources
    allInstantSettings: function () {
      return `${this.currentConfig.showLineAddress}|${this.currentConfig.showTimestamp}|${this.currentConfig.showAscii}|${this.currentConfig.newestAtTop}|${this.pauseOffset}`
    },
    allDebouncedSettings: function () {
      return `${this.currentConfig.bytesPerLine}|${this.currentConfig.packetsToShow}|${this.filterText}`
    },
  },
  watch: {
    latestData: function (data) {
      data.forEach((packet) => {
        if ('buffer' in packet) {
          packet.buffer = atob(packet.buffer)
        }
        this.historyPointer = ++this.historyPointer % this.currentConfig.history
        if (isNaN(this.historyPointer)) {
          this.historyPointer = 0
        }
        this.history[this.historyPointer] = packet
        if (!this.paused) {
          this.rebuildDisplayText()
        }
      })
    },
    paused: function (val) {
      if (val) {
        this.pausedAt = this.historyPointer
        this.pausedHistory = this.history.slice()
      } else {
        this.pauseOffset = 0
        this.rebuildDisplayText()
      }
    },
    allInstantSettings: function () {
      this.rebuildDisplayText()
    },
    allDebouncedSettings: _.debounce(function () {
      this.rebuildDisplayText()
    }, 300),
  },
  created: function () {
    const defaultConfig = {
      history: 300, // 5min at 1Hz
      showTimestamp: true,
      showAscii: true,
      showLineAddress: true,
      packetsToShow: 1,
      bytesPerLine: 16,
      newestAtTop: true,
    }
    this.currentConfig = {
      ...defaultConfig, // In case anything isn't defined in this.currentConfig
      ...this.currentConfig,
    }
  },
  mounted: function () {
    this.textarea = this.$refs.textarea.$el.querySelectorAll('textarea')[0]
  },
  methods: {
    rebuildDisplayText: function () {
      let packets = this.paused ? this.pausedHistory : this.history
      // Order packets chronologically and filter out the ones that aren't needed
      const breakpoint = this.paused ? this.pausedAt : this.historyPointer
      packets = packets
        .filter((packet) => packet) // in case history hasn't been filled yet
        .slice(breakpoint + 1, this.currentConfig.history)
        .concat(packets.slice(0, breakpoint + 1))
        .map(this.calculatePacketText) // convert to display text
        .map(this.matchesSearch)
      if (this.paused) {
        // Remove any that are after the slider (offset)
        const sliderPosition = Math.max(packets.length + this.pauseOffset, 1) // Always show at least one
        packets = packets.slice(0, sliderPosition)
      }
      // Take however many are supposed to be shown
      const end = Math.max(this.currentConfig.packetsToShow, 1) // Always show at least one
      packets = packets.slice(-end)
      if (this.currentConfig.newestAtTop) {
        packets = packets.reverse()
      }
      let join = '\n'
      if (this.filterText !== null) {
        join += '\n'
      }
      this.displayText = packets.join(join)
      this.rows = this.displayText.split('\n').length
    },
    matchesSearch: function (text) {
      if (this.filterText === null) {
        return text
      }
      return text
        .split('\n')
        .filter((line) =>
          line.toLowerCase().includes(this.filterText.toLowerCase()),
        )
        .join('\n')
    },
    download: function () {
      const blob = new Blob([this.displayText], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      let url = URL.createObjectURL(blob)
      link.href = url
      link.setAttribute(
        'download',
        `${format(new Date(), 'yyyy_MM_dd_HH_mm_ss')}.txt`,
      )
      link.click()
      window.URL.revokeObjectURL(url)
    },
    pause: function () {
      this.paused = true
    },
    togglePlayPause: function () {
      this.paused = !this.paused
    },
    stepBackward: function () {
      this.pause()
      this.pauseOffset--
    },
    stepForward: function () {
      this.pause()
      this.pauseOffset++
    },
  },
}
</script>

<style>
/* Flash the chevron icon 3 times to let the user know they can minimize the controls */
i.v-icon.mdi-chevron-down {
  animation: pulse 2s 3;
}
@keyframes pulse {
  0% {
    -webkit-box-shadow: 0 0 0 0 rgba(255, 255, 255, 0.4);
  }
  70% {
    -webkit-box-shadow: 0 0 0 10px rgba(255, 255, 255, 0);
  }
  100% {
    -webkit-box-shadow: 0 0 0 0 rgba(255, 255, 255, 0);
  }
}
</style>
<style lang="scss" scoped>
.text-area-container {
  position: relative;
  .v-textarea {
    font-family: 'Courier New', Courier, monospace;
  }

  .floating-buttons {
    position: absolute;
    top: 12px;
    right: 24px;
  }
}
.pulse {
  animation: pulse 2s infinite;
}
@keyframes pulse {
  0% {
    opacity: 1;
  }
  50% {
    opacity: 0.5;
  }
}
</style>
