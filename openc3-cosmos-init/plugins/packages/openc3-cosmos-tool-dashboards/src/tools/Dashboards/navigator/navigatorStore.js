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
import { Api } from '@openc3/js-common/services'
import { parseDashboard } from '../dashboardParser'
import { dashboardStyle } from '../dashboardStyle'
import { readJson, writeJson } from '../composables/storage'

const STARRED_KEY = 'dashboards__starred'
const RECENT_KEY = 'dashboards__recent'
const RECENT_MAX = 10

// A JSON array of 'TARGET/NAME'; anything else in storage is ignored
function keyList(storageKey) {
  const value = readJson(storageKey, [])
  return Array.isArray(value)
    ? value.filter((key) => typeof key === 'string')
    : []
}

// Per browser stars and recently opened dashboards, plus a cache of what each
// dashboard contains (title, icon, panel count) for the navigator
export const navigator = reactive({
  starred: keyList(STARRED_KEY),
  // Newest first
  recent: keyList(RECENT_KEY),
  // 'TARGET/NAME' => { title, icon, color, panels }
  info: {},
})

export function isStarred(key) {
  return navigator.starred.includes(key)
}

export function toggleStar(key) {
  navigator.starred = isStarred(key)
    ? navigator.starred.filter((k) => k !== key)
    : [...navigator.starred, key]
  writeJson(STARRED_KEY, navigator.starred)
}

export function visited(key) {
  navigator.recent = [key, ...navigator.recent.filter((k) => k !== key)].slice(
    0,
    RECENT_MAX,
  )
  writeJson(RECENT_KEY, navigator.recent)
}

export function forget(key) {
  delete navigator.info[key]
  if (navigator.recent.includes(key)) {
    navigator.recent = navigator.recent.filter((k) => k !== key)
    writeJson(RECENT_KEY, navigator.recent)
  }
}

// Summary of a parsed dashboard
function describe(model) {
  return {
    ...dashboardStyle(model.settings),
    title: model.title,
    panels: model.panels.length,
  }
}

// API URL of a saved dashboard ('TARGET/NAME'). Keys can come from the page
// URL, so each part is encoded to stay one path segment.
export function dashboardUrl(key) {
  const [target, name] = key.split('/')
  return `/openc3-api/dashboard/${encodeURIComponent(target)}/${encodeURIComponent(name)}`
}

// Text of a saved dashboard ('TARGET/NAME')
export async function fetchDashboardText(key) {
  const response = await Api.get(dashboardUrl(key), {
    headers: { Accept: 'text/plain', 'Ignore-Errors': '404' },
  })
  return response.data
}

// Keep a dashboard's summary current when it's opened or saved. Takes the
// parsed model the caller already has.
export function remember(key, model) {
  navigator.info[key] = describe(model)
}

// Keys queued or being fetched, so a row scrolled past twice fetches once
const pending = new Set()
const queue = []
const WORKERS = 4
let running = 0

async function work() {
  running++
  while (queue.length) {
    // Newest first: the rows on screen now
    const key = queue.pop()
    try {
      const { model } = parseDashboard(await fetchDashboardText(key))
      navigator.info[key] = describe(model)
    } catch {
      // Leave it out; the list still shows the name
    } finally {
      pending.delete(key)
    }
  }
  running--
}

// Fill in info for a dashboard not seen yet this session, when its row is
// first shown, so hundreds of dashboards don't mean hundreds of fetches up
// front. Ones that are opened or saved stay current through remember().
export function loadInfo(key) {
  if (navigator.info[key] || pending.has(key)) return
  pending.add(key)
  queue.push(key)
  if (running < WORKERS) work()
}
