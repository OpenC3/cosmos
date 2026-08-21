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

// Process-wide cache for settings fetched via OpenC3Api.get_settings.
// Settings change rarely; the admin UI tells users to refresh after edits, so
// a write-once-per-session cache is the documented contract.
const cache = new Map()
const inflight = new Map()

// Requests made in the same tick are coalesced into one get_settings call.
// Page load mounts a handful of components that each want a different setting
// (theme, astro, subtitle, time_zone, ...); as separate requests they were a
// burst of round trips, and a burst of server side auth errors when the token
// was stale.
let batch = null
// Bumped by resetSettingsCache so a batch queued before the reset doesn't write
// its results into the cache afterwards. It still settles its promises - callers
// are already awaiting them and must not be left hanging.
let generation = 0

// cacheable is false when the value is a fallback we made up because the
// request failed. Caching that would pin every setting in the batch to its
// default for the rest of the session, so a transient failure (network blip, a
// 401 while the token is being refreshed) would look permanent. Settle the
// promise so callers aren't left hanging, but leave the cache empty so the next
// caller retries.
function settle(entry, value, batchGeneration, cacheable = true) {
  if (batchGeneration === generation) {
    inflight.delete(entry.name)
    if (cacheable) {
      cache.set(entry.name, value)
    }
  }
  entry.resolve(value)
}

// entries is captured by the caller rather than read from `batch`, which the
// reset can null out before this microtask runs
function flushBatch(entries, batchGeneration) {
  if (batch === entries) {
    batch = null
  }
  new OpenC3Api()
    .get_settings(entries.map((entry) => entry.name))
    .then((response) => {
      entries.forEach((entry, index) => {
        settle(entry, response?.[index] ?? entry.fallback, batchGeneration)
      })
    })
    .catch(() => {
      entries.forEach((entry) =>
        settle(entry, entry.fallback, batchGeneration, false),
      )
    })
}

export function getCachedSetting(name, fallback) {
  if (cache.has(name)) {
    return Promise.resolve(cache.get(name))
  }
  if (!inflight.has(name)) {
    let resolve
    inflight.set(
      name,
      new Promise((res) => {
        resolve = res
      }),
    )
    if (batch === null) {
      const entries = []
      const batchGeneration = generation
      batch = entries
      queueMicrotask(() => flushBatch(entries, batchGeneration))
    }
    batch.push({ name, fallback, resolve })
  }
  return inflight.get(name)
}

export function peekCachedSetting(name) {
  return cache.has(name) ? cache.get(name) : undefined
}

// Drop a single setting so the next getCachedSetting refetches it. For the few
// components that poll a setting on an interval and would otherwise be served
// the same cached value forever (see ContextTag).
export function invalidateCachedSetting(name) {
  cache.delete(name)
}

export function resetSettingsCache() {
  cache.clear()
  inflight.clear()
  batch = null
  generation += 1
}
