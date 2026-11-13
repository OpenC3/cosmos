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

// Panel types from plugins. A plugin's plugin.txt has
//
//   PANEL MAP
//
// and ships tools/panels/MAP/MAP.js, a SystemJS module (vue and vuetify
// external) whose default export is a function taking the panel SDK below
// and returning a panel type definition, the same shape as an entry in
// panels/registry.js:
//
//   export default (sdk) => ({
//     label: 'Map',
//     icon: 'mdi-map-outline',
//     component: MapPanel, // <script setup> calling sdk.useTlmPanel(props)
//     content: 'items',
//     options: [...],
//   })
//
// `cli generate panel MapPanel` scaffolds one; see
// https://docs.openc3.com/docs/guides/custom-panels

import { Api } from '@openc3/js-common/services'
import { registerPanelType } from '../panels/registry'
import { panelProps, usePanel } from '../panels/panelBase'
import { itemLabel, pollType, useTlmPanel } from '../panels/tlmPanel'
import { useTlmSeries } from '../panels/tlmSeries'
import { itemOption, option, withOption } from '../panels/options'
import { SERIES_COLORS, seriesColor } from '../panels/colors'
import { baseKey, itemKey, packetTimeKey } from './tlmPoller'
import {
  clock,
  compactNumber,
  formatItem,
  formatTelemetry,
  formatTime,
  toSeconds,
} from './format'
import { stateToLevel, worstLevel } from '../status'
import LimitsBar from '../components/LimitsBar.vue'
import Sparkline from '../components/Sparkline.vue'
import StatusSymbol from '../components/StatusSymbol.vue'

// What plugin panels can use. Bump `version` on breaking changes so plugins
// can check it.
export const PANEL_SDK = Object.freeze({
  version: 1,
  // Composables: usePanel (polling and status plumbing), useTlmPanel (adds
  // itemStates for the panel's ITEMs), useTlmSeries (history over the
  // dashboard's time range). Panels take panelProps.
  panelProps,
  usePanel,
  useTlmPanel,
  useTlmSeries,
  // Options and items
  option,
  withOption,
  itemOption,
  itemKey,
  baseKey,
  packetTimeKey,
  pollType,
  itemLabel,
  // Formatting and status
  // Times: panels get the user's time zone as timeZone (usePanel)
  formatTelemetry,
  formatItem,
  formatTime,
  toSeconds,
  clock,
  compactNumber,
  stateToLevel,
  worstLevel,
  SERIES_COLORS,
  seriesColor,
  // Building blocks that match the built-in panels
  components: { LimitsBar, Sparkline, StatusSymbol },
})

let loading = null

// Load every installed panel type before dashboards are parsed, once per
// page. Resolves to the problems found, so the page can report them without
// failing to load.
export function loadPanelPlugins() {
  loading ||= load()
  return loading
}

async function load() {
  let names = []
  try {
    names = (await Api.get('/openc3-api/panels')).data
  } catch (error) {
    return [`Could not list plugin panels: ${error.message}`]
  }
  const results = await Promise.all(
    names.map(async (name) => {
      // Plugins can only install plain names (PanelModel); anything else
      // isn't loaded as a script path
      if (!/^[A-Z0-9_-]+$/.test(name)) return `Invalid panel name ${name}`
      try {
        const module = await window.System.import(
          `/tools/panels/${name}/${name}.js`,
        )
        const exported = module.default ?? module
        const definition =
          typeof exported === 'function' ? exported(PANEL_SDK) : exported
        return registerPanelType(name, definition)
      } catch (error) {
        return `Panel ${name} failed to load: ${error.message || error}`
      }
    }),
  )
  return results.filter(Boolean)
}
