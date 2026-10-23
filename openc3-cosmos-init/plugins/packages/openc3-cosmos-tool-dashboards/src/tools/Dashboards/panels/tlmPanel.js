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

import panelBase from './panelBase'
import { itemKey, packetTimeKey } from '../composables/tlmPoller'
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

// Fetches units, format and limits for the panel's items before the
// computeds read them. Part of tlmPanel; panels that only need panelBase
// (e.g. GRAPH) mix it in themselves.
export const prefetchItemInfo = {
  watch: {
    'panel.items': {
      immediate: true,
      handler(items) {
        for (const item of items) this.itemInfo.get(item)
      },
    },
  },
}

// Panels that show polled telemetry for their ITEMs. `itemStates` has what
// each item needs to render: formatted text, number, units, limits, status.
export default {
  mixins: [panelBase, prefetchItemInfo],
  computed: {
    pollKeys() {
      const keys = new Set(
        this.panel.items.map((item) => itemKey(item, pollType(item))),
      )
      if (this.packetTimeKey) keys.add(this.packetTimeKey)
      for (const key of this.extraPollKeys()) keys.add(key)
      return [...keys]
    },
    itemStates() {
      const labels = itemLabels(this.panel.items)
      return this.panel.items.map((item, index) => {
        const polled = this.poller.values[itemKey(item, pollType(item))]
        const info = this.itemInfo.get(item)
        const raw = item.valueType === 'RAW'
        return {
          item,
          key: itemKey(item),
          label: labels[index],
          path: `${item.targetName} ${item.packetName} ${item.itemName}`,
          number: typeof polled?.value === 'number' ? polled.value : null,
          text: formatItem(
            item.itemName,
            polled?.value,
            raw ? null : info.formatString,
            this.timeZone,
          ),
          units: raw ? '' : info.units,
          level: stateToLevel(polled?.state),
          stale: polled?.state === 'STALE',
          changedAt: polled?.changedAt,
          limits: this.itemInfo.limits(item),
        }
      })
    },
    // Single value panels show the first item
    first() {
      return this.itemStates[0] || { text: '--', units: '' }
    },
    // Received time of the first item's packet, to the second, for panel
    // types that declare a PACKET_TIME option and have it on
    packetTimeKey() {
      const item = this.panel.items[0]
      return item && option(this.panel, 'PACKET_TIME')
        ? packetTimeKey(item)
        : null
    },
    packetTime() {
      const time = this.poller.values[this.packetTimeKey]?.value ?? ''
      return toSeconds(formatTime(time, this.timeZone))
    },
    panelLevel() {
      return worstLevel(this.itemStates.map((state) => state.level))
    },
  },
  methods: {
    // Panels override this to poll more keys than their items
    extraPollKeys() {
      return []
    },
    // Opens the details sheet, where offered, for an item (default: the first)
    showDetails(item = this.first.item) {
      if (this.openDetails && item) this.openDetails(item)
    },
  },
}
