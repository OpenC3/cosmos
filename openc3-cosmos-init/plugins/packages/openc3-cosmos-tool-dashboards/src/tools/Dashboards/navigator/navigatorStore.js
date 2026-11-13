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
import { dashboardStyle } from '../dashboardStyle'
import { readJson, writeJson } from '../composables/storage'

const STARRED_KEY = 'dashboards__starred'

// A JSON array of 'TARGET/NAME'; anything else in storage is ignored
function keyList(storageKey) {
  const value = readJson(storageKey, [])
  return Array.isArray(value)
    ? value.filter((key) => typeof key === 'string')
    : []
}

// Per browser stars, plus a cache of what each dashboard contains (title,
// icon, panel count) for the navigator
export const navigator = reactive({
  starred: keyList(STARRED_KEY),
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

export function forget(key) {
  delete navigator.info[key]
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

// 'TARGET/NAME' for a dashboard file path from the API (TARGET/dashboards/
// name.txt), the way Dashboards names them
export function dashboardKey(path) {
  const [target, , file] = path.split('/')
  return `${target}/${file.replace(/\.txt$/, '').toUpperCase()}`
}

let summaries = null

// Fill in every dashboard's info with one request, once per page; the server
// reads the files (GET /openc3-api/dashboards?summary=true). Ones opened or
// saved since are kept, since remember() has them current. A failed request
// is tried again on the next call.
export function loadSummaries() {
  summaries ||= Api.get('/openc3-api/dashboards', {
    params: { summary: true },
  })
    .then(({ data }) => {
      for (const entry of data) {
        // An older API ignores summary=true and lists paths only
        if (typeof entry !== 'object') continue
        const { path, title, icon, color, panels } = entry
        navigator.info[dashboardKey(path)] ??= {
          ...dashboardStyle({ ICON: [icon], COLOR: [color] }),
          title,
          panels,
        }
      }
    })
    .catch(() => {
      summaries = null
    })
  return summaries
}
