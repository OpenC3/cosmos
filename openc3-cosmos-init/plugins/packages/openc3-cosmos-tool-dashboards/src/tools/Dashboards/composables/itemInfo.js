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
import { OpenC3Api } from '@openc3/js-common/services'
import { baseKey } from './tlmPoller'

const LIMITS_SET_REFRESH_MS = 10000

// Caches get_item results (units, format, limits) for every item a dashboard
// shows and tracks the current limits set so limits bars follow set changes.
export class ItemInfo {
  constructor() {
    this.api = new OpenC3Api()
    this.state = reactive({ items: {}, limitsSet: 'DEFAULT' })
    this.timer = null
  }

  start() {
    this.refreshLimitsSet()
    this.timer = setInterval(
      () => this.refreshLimitsSet(),
      LIMITS_SET_REFRESH_MS,
    )
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  refreshLimitsSet() {
    this.api
      .get_limits_set()
      .then((set) => {
        if (set) this.state.limitsSet = set
      })
      .catch(() => {
        // Keep the last known set
      })
  }

  // Reactive info for an item ({ targetName, packetName, itemName }),
  // fetched the first time it's asked for. Panels call this from a watcher
  // before rendering so computeds only read.
  get(item) {
    const key = baseKey(item)
    if (!this.state.items[key]) {
      this.state.items[key] = {
        loaded: false,
        units: '',
        formatString: null,
        description: '',
        limits: null,
      }
      this.api
        .get_item(item.targetName, item.packetName, item.itemName)
        .then((info) => {
          Object.assign(this.state.items[key], {
            loaded: true,
            units: info.units || '',
            formatString: info.format_string || null,
            description: info.description || '',
            limits: info.limits || null,
          })
        })
        .catch(() => {
          this.state.items[key].loaded = true
        })
    }
    return this.state.items[key]
  }

  // Limits values for the current set: { red_low, yellow_low, yellow_high,
  // red_high, green_low?, green_high? } or null if the item has no limits
  limits(item) {
    const info = this.get(item)
    if (!info.limits) return null
    return info.limits[this.state.limitsSet] || info.limits.DEFAULT || null
  }
}
