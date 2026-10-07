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

const STARRED_KEY = 'dashboards__starred'

function readList(key) {
  try {
    const value = JSON.parse(localStorage[key] || '[]')
    return Array.isArray(value) ? value : []
  } catch {
    return []
  }
}

function writeList(key, list) {
  try {
    localStorage[key] = JSON.stringify(list)
  } catch {
    // Storage unavailable (private window); stars just don't stick
  }
}

// Per browser stars, plus a cache of what each
// dashboard contains (title, panel count, targets) for the navigator
export const navigator = reactive({
  starred: readList(STARRED_KEY),
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
  writeList(STARRED_KEY, navigator.starred)
}

export function forget(key) {
  delete navigator.info[key]
}

// Summary of a dashboard from its text
function describe(text) {
  const { model } = parseDashboard(text)
  const targets = new Set()
  for (const panel of model.panels) {
    for (const item of panel.items) targets.add(item.targetName)
    for (const target of panel.targets) targets.add(target)
    if (panel.command) targets.add(panel.command.targetName)
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

// Keep a dashboard's summary current when it's opened or saved
export function remember(key, text) {
  navigator.info[key] = describe(text)
}

// Fill in info for dashboards not seen yet this session; ones that are opened
// or saved stay current through remember()
export async function loadInfo(keys) {
  const missing = keys.filter((key) => !navigator.info[key])
  const results = await Promise.all(
    missing.map((key) =>
      fetchDashboardText(key)
        .then((text) => [key, describe(text)])
        // Leave it out; the list still shows the name
        .catch(() => null),
    ),
  )
  for (const result of results) {
    if (result) navigator.info[result[0]] = result[1]
  }
}
