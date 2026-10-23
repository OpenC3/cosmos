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

// Telemetry Viewer screen files, read by SCREEN panels and edited from their
// panel dialog. Saving bumps the screen's revision so every panel showing it
// reloads.

// 'TARGET/SCREEN' => number of saves this page has made
export const screenRevisions = reactive({})

export function screenKey(screen) {
  return screen ? `${screen.targetName}/${screen.screenName}` : null
}

let screenList = null

// Every screen as { TARGET: [SCREEN, ...] }, fetched once per page (saving a
// screen refetches, so a new one is listed). A failed fetch is retried on the
// next call. Callers copy before changing it.
export function listScreens() {
  screenList ||= Api.get('/openc3-api/screens')
    .then((response) => {
      const screens = {}
      for (const path of response.data) {
        const [target, , file] = path.split('/')
        ;(screens[target] ||= []).push(file.replace(/\.txt$/, '').toUpperCase())
      }
      return screens
    })
    .catch((error) => {
      screenList = null
      throw error
    })
  return screenList
}

// The screen's definition text. Throws when it doesn't exist.
export async function loadScreen(screen) {
  // Names come from the dashboard file, so they're encoded
  const target = encodeURIComponent(screen.targetName)
  const name = encodeURIComponent(screen.screenName)
  const response = await Api.get(`/openc3-api/screen/${target}/${name}`, {
    headers: { Accept: 'text/plain', 'Ignore-Errors': '404' },
  })
  return response.data
}

export async function saveScreen(screen, text) {
  await Api.post('/openc3-api/screen/', {
    data: {
      scope: window.openc3Scope,
      target: screen.targetName,
      screen: screen.screenName,
      text,
    },
  })
  screenList = null
  const key = screenKey(screen)
  screenRevisions[key] = (screenRevisions[key] || 0) + 1
}

// Starting text for a new screen, like Telemetry Viewer's New Screen: a
// LABELVALUE for every item in `packetName`, or a placeholder label
export async function newScreenText(api, targetName, packetName) {
  let text = 'SCREEN AUTO AUTO 1.0\n'
  if (!packetName) return `${text}\nLABEL NEW\n`
  const packet = await api.get_tlm(targetName, packetName)
  text += '\nVERTICAL\n'
  for (const item of packet.items) {
    if (item.hidden) continue
    // Brackets are doubled so they aren't read as array indexes
    const name = item.name.replace(/\[/g, '[[').replace(/\]/g, ']]')
    text += `  LABELVALUE ${targetName} ${packetName} ${name}\n`
  }
  return `${text}END\n`
}
