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

import { reactive } from 'vue'

// Playback: every panel shows telemetry as of a past time. The poller
// looks values up at the playback time instead of polling; panels read
// { on, time } (provided as 'timeline').
export function usePlayback(poller) {
  const playback = reactive({ on: false, time: null })

  function setPlaybackTime(time) {
    playback.time = time
    poller.setPlaybackTime(time)
  }
  function goLive() {
    playback.on = false
    setPlaybackTime(null)
  }

  return { playback, setPlaybackTime, goLive }
}
