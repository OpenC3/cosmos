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

import { computed, inject, onMounted, onUnmounted, unref, watch } from 'vue'
import { stateToLevel, worstLevel } from '../status'

// The props every panel takes. Panels spread these into defineProps.
export const panelProps = {
  panel: { type: Object, required: true },
}

// What every panel shares: the dashboard services, keeping the poller
// registrations in step with `pollKeys`, and reporting the worst status
// shown (`panelLevel`) to the grid.
//
// Panels pass getters for what they poll and the level they show:
//
//   const props = defineProps(panelProps)
//   const { poller, worstOf } = usePanel(props, {
//     pollKeys: () => keys.value,
//     panelLevel: () => worstOf(keys.value),
//   })
//
// The getters are first read when the panel mounts, so they can use
// computeds declared after this call.
export function usePanel(props, options = {}) {
  const poller = inject('poller')
  const itemInfo = inject('itemInfo')
  // One streaming connection for the whole dashboard
  const cable = inject('cable', null)
  // Opens the item details sheet; absent where details aren't offered
  const openDetails = inject('openDetails', null)
  // { on } while the dashboard is being edited: telemetry keeps flowing,
  // but panels don't send commands or run anything
  const editing = inject('editing', () => ({ on: false }), true)
  // { on, time }: while playback is on, panels show telemetry as of `time`
  const timeline = inject('timeline', () => ({ on: false, time: null }), true)
  // 'local' or 'UTC', from Admin > Settings: times show in it (format.js)
  const injectedTimeZone = inject('timeZone', 'local')
  // { uid: rect } as drawn, including mid-drag (DashboardGrid)
  const gridRects = inject('gridRects', null)
  // { uid: level } read by the grid's frames and health chip; absent where
  // panels are shown outside a grid
  const panelLevels = inject('panelLevels', null)

  const timeZone = computed(() => unref(injectedTimeZone))
  const isEditing = computed(() => editing.on)
  // Not editing, so actions are allowed
  const isLive = computed(() => !editing.on)
  // The panel's size and place as drawn: follows a resize while it's being
  // dragged and the tablet / phone layouts. Use instead of panel.w / h.
  const rect = computed(
    () => unref(gridRects)?.[props.panel.uid] ?? props.panel,
  )
  const isPlayback = computed(() => timeline.on)
  // The Date being played back, null until playback starts
  const playbackTime = computed(() => (timeline.on ? timeline.time : null))
  const pollKeys = computed(() => options.pollKeys?.() ?? [])
  const panelLevel = computed(() => options.panelLevel?.() ?? null)

  // Worst status across polled keys
  function worstOf(keys) {
    return worstLevel(
      keys.map((key) => stateToLevel(poller.values[key]?.state)),
    )
  }

  // Fetch units, format and limits before the computeds read them
  function prefetch(items) {
    for (const item of items ?? []) itemInfo.get(item)
  }
  prefetch(props.panel.items)

  onMounted(() => {
    poller.register(pollKeys.value)
    // The poller is outside Vue, so keep its registrations in step by hand.
    // A new panel config (items) comes in as a new prop, with no event.
    watch(pollKeys, (newKeys, oldKeys) => {
      prefetch(props.panel.items)
      poller.unregister(oldKeys)
      poller.register(newKeys)
    })
    // The grid reads the computed itself, so it stays current
    if (panelLevels) panelLevels[props.panel.uid] = panelLevel
  })
  onUnmounted(() => {
    poller.unregister(pollKeys.value)
    if (panelLevels) {
      // Virtualized panels keep their last report. Deleting first, or the
      // reactive object would write through to the computed.
      const level = panelLevel.value
      delete panelLevels[props.panel.uid]
      panelLevels[props.panel.uid] = level
    }
  })

  return {
    poller,
    itemInfo,
    cable,
    openDetails,
    editing,
    timeline,
    timeZone,
    isEditing,
    isLive,
    rect,
    isPlayback,
    playbackTime,
    pollKeys,
    panelLevel,
    worstOf,
  }
}
