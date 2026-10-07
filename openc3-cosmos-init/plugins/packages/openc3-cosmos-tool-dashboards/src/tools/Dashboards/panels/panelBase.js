/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { stateToLevel, worstLevel } from '../status'

// What every panel shares: the dashboard services, the panel prop, keeping
// the poller registrations in step with `pollKeys`, and reporting the worst
// status shown (`panelLevel`) to the frame. Panels override the two
// computeds.
export default {
  inject: {
    poller: 'poller',
    itemInfo: 'itemInfo',
    // One streaming connection for the whole dashboard
    cable: { default: null },
    // Opens the item details sheet; absent where details aren't offered
    openDetails: { default: null },
    // { on } is false while the dashboard is being edited; panels stop
    // fetching telemetry and sending commands until it's back on
    live: { default: () => ({ on: true }) },
    // { on, time }: while playback is on, panels show telemetry as of `time`
    timeline: { default: () => ({ on: false, time: null }) },
  },
  props: {
    panel: { type: Object, required: true },
  },
  emits: ['level'],
  computed: {
    isLive() {
      return this.live.on
    },
    isPlayback() {
      return this.timeline.on
    },
    // The Date being played back, null until playback starts
    playbackTime() {
      return this.timeline.on ? this.timeline.time : null
    },
    pollKeys() {
      return []
    },
    panelLevel() {
      return null
    },
  },
  watch: {
    pollKeys(newKeys, oldKeys) {
      this.poller.unregister(oldKeys)
      this.poller.register(newKeys)
    },
    panelLevel: {
      immediate: true,
      handler(level) {
        this.$emit('level', level)
      },
    },
  },
  mounted() {
    this.poller.register(this.pollKeys)
  },
  unmounted() {
    this.poller.unregister(this.pollKeys)
  },
  methods: {
    // Worst status across polled keys
    worstOf(keys) {
      return worstLevel(
        keys.map((key) => stateToLevel(this.poller.values[key]?.state)),
      )
    },
  },
}
