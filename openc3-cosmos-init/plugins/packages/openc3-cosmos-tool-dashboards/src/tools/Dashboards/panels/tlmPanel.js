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
import { formatTelemetry, toSeconds } from '../composables/format'
import { option } from './options'
import { stateToLevel } from '../status'

// The value type an item is polled as. CONVERTED carries the number, the
// state name and the limits state; formatting happens on the client.
export function pollType(item) {
  return item.valueType === 'RAW' ? 'RAW' : 'CONVERTED'
}

// Label for an item, with its target only when the items mix targets
export function itemLabel(items, item) {
  const multiTarget = new Set(items.map((i) => i.targetName)).size > 1
  return multiTarget ? `${item.targetName} ${item.itemName}` : item.itemName
}

// Panels that show polled telemetry for their ITEMs. `itemStates` has what
// each item needs to render: formatted text, number, units, limits, status.
export default {
  mixins: [panelBase],
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
      return this.panel.items.map((item) => {
        const polled = this.poller.values[itemKey(item, pollType(item))]
        const info = this.itemInfo.get(item)
        const raw = item.valueType === 'RAW'
        return {
          item,
          key: itemKey(item),
          label: itemLabel(this.panel.items, item),
          path: `${item.targetName} ${item.packetName} ${item.itemName}`,
          number: typeof polled?.value === 'number' ? polled.value : null,
          text: formatTelemetry(polled?.value, raw ? null : info.formatString),
          units: raw ? '' : info.units,
          level: stateToLevel(polled?.state),
          stale: polled?.state === 'STALE',
          changedAt: polled?.changedAt,
          limits: this.itemInfo.limits(item),
        }
      })
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
      return toSeconds(this.poller.values[this.packetTimeKey]?.value ?? '')
    },
    panelLevel() {
      return this.worstOf(
        this.panel.items.map((item) => itemKey(item, pollType(item))),
      )
    },
  },
  watch: {
    // Fetch units, format and limits before the computeds read them
    'panel.items': {
      immediate: true,
      handler(items) {
        for (const item of items) this.itemInfo.get(item)
      },
    },
  },
  methods: {
    // Panels override this to poll more keys than their items
    extraPollKeys() {
      return []
    },
  },
}
