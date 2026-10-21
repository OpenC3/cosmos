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

// A JSON array of 'TARGET/NAME'
function starredList() {
  const value = readJson(STARRED_KEY, [])
  return Array.isArray(value) ? value : []
}

// Per browser stars, plus a cache of what each
// dashboard contains (title, panel count, targets) for the navigator
export const navigator = reactive({
  starred: starredList(),
  // 'TARGET/NAME' => { title, panels, targets: [] }
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

export function forget(key) {
  delete navigator.info[key]
}

// Summary of a parsed dashboard
function describe(model) {
  const targets = new Set()
  for (const panel of model.panels) {
    for (const item of panel.items) targets.add(item.targetName)
    for (const target of panel.targets) targets.add(target)
    if (panel.command) targets.add(panel.command.targetName)
    if (panel.screen) targets.add(panel.screen.targetName)
  }
  return {
    ...dashboardStyle(model.settings),
    title: model.title,
    panels: model.panels.length,
    targets: [...targets].sort(),
  }
}

// Text of a saved dashboard ('TARGET/NAME')
export async function fetchDashboardText(key) {
  const [target, name] = key.split('/')
  const response = await Api.get(`/openc3-api/dashboard/${target}/${name}`, {
    headers: { Accept: 'text/plain', 'Ignore-Errors': '404' },
  })
  return response.data
}

// Keep a dashboard's summary current when it's opened or saved. Takes the
// parsed model the caller already has.
export function remember(key, model) {
  navigator.info[key] = describe(model)
}

// Keys being fetched, so reopening the navigator mid-fetch doesn't fetch twice
const loading = new Set()

// Fill in info for dashboards not seen yet this session; ones that are opened
// or saved stay current through remember()
export async function loadInfo(keys) {
  const missing = keys.filter(
    (key) => !navigator.info[key] && !loading.has(key),
  )
  await Promise.all(
    missing.map(async (key) => {
      loading.add(key)
      try {
        const { model } = parseDashboard(await fetchDashboardText(key))
        navigator.info[key] = describe(model)
      } catch {
        // Leave it out; the list still shows the name
      } finally {
        loading.delete(key)
      }
    }),
  )
}
