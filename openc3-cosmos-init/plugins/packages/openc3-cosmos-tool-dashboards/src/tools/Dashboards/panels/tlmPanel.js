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

import { computed } from 'vue'
import { usePanel } from './panelBase'
import { itemKey, packetTimeKey as timeKeyOf } from '../composables/tlmPoller'
import { formatItem, formatTime, toSeconds } from '../composables/format'
import { option } from './options'
import { stateToLevel, worstLevel } from '../status'

// The value type an item is polled as. CONVERTED carries the number, the
// state name and the limits state; formatting happens on the client.
export function pollType(item) {
  return item.valueType === 'RAW' ? 'RAW' : 'CONVERTED'
}

function mixesTargets(items) {
  return new Set(items.map((i) => i.targetName)).size > 1
}

function label(item, multiTarget) {
  return multiTarget ? `${item.targetName} ${item.itemName}` : item.itemName
}

// Label for an item, with its target only when the items mix targets
export function itemLabel(items, item) {
  return label(item, mixesTargets(items))
}

// Labels for all the items, checking for mixed targets once
export function itemLabels(items) {
  const multiTarget = mixesTargets(items)
  return items.map((item) => label(item, multiTarget))
}

// Panels that show polled telemetry for their ITEMs. `itemStates` has what
// each item needs to render: formatted text, number, units, limits, status.
// Takes usePanel's options plus `extraPollKeys` (a getter for keys to poll
// besides the items); `panelLevel` defaults to the worst item level.
export function useTlmPanel(props, options = {}) {
  const base = usePanel(props, {
    pollKeys: () => pollKeys.value,
    panelLevel: () =>
      options.panelLevel
        ? options.panelLevel()
        : worstLevel(itemStates.value.map((state) => state.level)),
  })
  const { poller, itemInfo, timeZone, openDetails } = base

  // Received time of the first item's packet, to the second, for panel
  // types that declare a PACKET_TIME option and have it on
  const packetTimeKey = computed(() => {
    const item = props.panel.items[0]
    return item && option(props.panel, 'PACKET_TIME') ? timeKeyOf(item) : null
  })
  const pollKeys = computed(() => {
    const keys = new Set(
      props.panel.items.map((item) => itemKey(item, pollType(item))),
    )
    if (packetTimeKey.value) keys.add(packetTimeKey.value)
    for (const key of options.extraPollKeys?.() ?? []) keys.add(key)
    return [...keys]
  })
  const itemStates = computed(() => {
    const labels = itemLabels(props.panel.items)
    return props.panel.items.map((item, index) => {
      const polled = poller.values[itemKey(item, pollType(item))]
      const info = itemInfo.get(item)
      const raw = item.valueType === 'RAW'
      return {
        item,
        key: itemKey(item),
        label: labels[index],
        path: `${item.targetName} ${item.packetName} ${item.itemName}`,
        // NaN has no place on a scale; ±Infinity pins to its ends
        number:
          typeof polled?.value === 'number' && !Number.isNaN(polled.value)
            ? polled.value
            : null,
        text: formatItem(
          item.itemName,
          polled?.value,
          raw ? null : info.formatString,
          timeZone.value,
        ),
        units: raw ? '' : info.units,
        level: stateToLevel(polled?.state),
        stale: polled?.state === 'STALE',
        changedAt: polled?.changedAt,
        limits: itemInfo.limits(item),
      }
    })
  })
  // Single value panels show the first item
  const first = computed(() => itemStates.value[0] || { text: '--', units: '' })
  const packetTime = computed(() => {
    const time = poller.values[packetTimeKey.value]?.value ?? ''
    return toSeconds(formatTime(time, timeZone.value))
  })

  // Opens the details sheet, where offered, for an item (default: the first)
  function showDetails(item = first.value.item) {
    if (openDetails && item) openDetails(item)
  }

  return {
    ...base,
    itemStates,
    first,
    packetTimeKey,
    packetTime,
    showDetails,
  }
}
