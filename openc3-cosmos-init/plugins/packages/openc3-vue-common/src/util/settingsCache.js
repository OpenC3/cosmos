/*
# Copyright 2026, OpenC3, Inc.
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

import { OpenC3Api } from '@openc3/js-common/services'

// Process-wide cache for settings fetched via OpenC3Api.get_setting.
// Settings change rarely; the admin UI tells users to refresh after edits, so
// a write-once-per-session cache is the documented contract.
const cache = new Map()
const inflight = new Map()

export function getCachedSetting(name, fallback) {
  if (cache.has(name)) {
    return Promise.resolve(cache.get(name))
  }
  if (!inflight.has(name)) {
    const promise = new OpenC3Api()
      .get_setting(name)
      .then((response) => {
        const value = response || fallback
        cache.set(name, value)
        return value
      })
      .catch(() => {
        cache.set(name, fallback)
        return fallback
      })
      .finally(() => {
        inflight.delete(name)
      })
    inflight.set(name, promise)
  }
  return inflight.get(name)
}

export function peekCachedSetting(name) {
  return cache.has(name) ? cache.get(name) : undefined
}

export function resetSettingsCache() {
  cache.clear()
  inflight.clear()
}
