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

// Every panel type is one entry here. The parser, serializer and panel dialog
// all read from this table.
//
//   category                    groups types in the panel type picker
//   label / description / icon  shown in the panel type picker
//   component                   renders the panel body inside PanelFrame,
//                               receives the `panel` prop
//   content                     panel dialog editor for what the panel shows
//                               (items, targets, a command); emits `update`
//   defaults                    width and height for a new panel
//   keywords                    keywords allowed inside PANEL ... END
//   maxItems                    limit on ITEM lines (null = unlimited)
//   itemOptions                 ITEM_SETTINGs each item understands, same
//                               format as options (e.g. a graph line COLOR)
//   options                     SETTINGs the panel understands, see options.js.
//                               Declaring one here is enough for it to parse,
//                               validate, save and show in the panel dialog;
//                               the panel reads it with option(panel, NAME).
//   title / subtitle            optional (panel) => string for the panel
//                               header; defaults describe the panel's items
//   validate                    optional (panel) => message when the panel is
//                               incomplete; panels with ITEM need one item
//   hidden                      left out of the panel type picker
//
// To add a panel type: write the panel component, reuse or write a content
// editor, and add an entry below. Plugins add types the same way through
// registerPanelType (see panelPlugins.js).

import GraphPanel from './GraphPanel.vue'
import ValuesPanel from './ValuesPanel.vue'
import LimitsPanel from './LimitsPanel.vue'
import StatPanel from './StatPanel.vue'
import StatePanel from './StatePanel.vue'
import CommandPanel from './CommandPanel.vue'
import UnknownPanel from './UnknownPanel.vue'
import ItemsConfig from './config/ItemsConfig.vue'
import LimitsConfig from './config/LimitsConfig.vue'
import CommandConfig from './config/CommandConfig.vue'

// Shared by panel types whose items are drawn as lines
const COLOR_OPTION = {
  name: 'COLOR',
  type: 'color',
  label: 'Color',
  default: null,
}

// Stands in for a panel whose type isn't installed (its plugin is missing)
export const UNKNOWN_TYPE = '__UNKNOWN__'

export const PANEL_TYPES = {
  STAT: {
    category: 'Telemetry',
    label: 'Stat',
    description: 'One value, big, with limits and a sparkline',
    icon: 'mdi-numeric',
    component: StatPanel,
    content: ItemsConfig,
    defaults: { w: 3, h: 3 },
    keywords: ['ITEM', 'ITEM_SETTING', 'SETTING'],
    maxItems: 1,
    itemOptions: [{ ...COLOR_OPTION, help: 'Color of the graph line' }],
    options: [
      {
        name: 'PACKET_TIME',
        type: 'boolean',
        label: 'Show packet time',
        default: true,
      },
      {
        name: 'GRAPH',
        type: 'boolean',
        label: 'Show graph',
        default: true,
      },
      {
        name: 'LIMITS_LINES',
        type: 'boolean',
        label: 'Show limits on the graph',
        default: true,
        when: (get) => get('GRAPH'),
      },
      {
        name: 'LIMITS_BAR',
        type: 'boolean',
        label: 'Show limits bar',
        default: true,
      },
    ],
  },
  STATE: {
    category: 'Telemetry',
    label: 'State',
    description: 'Current state of an item, with its packet time',
    icon: 'mdi-toggle-switch-outline',
    component: StatePanel,
    content: ItemsConfig,
    defaults: { w: 3, h: 3 },
    keywords: ['ITEM', 'SETTING'],
    maxItems: 1,
    options: [
      {
        name: 'PACKET_TIME',
        type: 'boolean',
        label: 'Show packet time',
        default: true,
      },
    ],
  },
  GRAPH: {
    category: 'Telemetry',
    label: 'Graph',
    description: 'Time series with limits thresholds',
    icon: 'mdi-chart-line',
    component: GraphPanel,
    content: ItemsConfig,
    defaults: { w: 8, h: 7 },
    keywords: ['ITEM', 'ITEM_SETTING', 'SETTING'],
    maxItems: 6,
    itemOptions: [
      { ...COLOR_OPTION, help: 'Defaults to the next series color' },
    ],
    options: [
      {
        name: 'DURATION',
        type: 'number',
        label: 'History shown',
        unit: 'minutes',
        default: 2,
        min: 0.5,
        max: 1440,
      },
      {
        name: 'THRESHOLDS',
        type: 'item',
        label: 'Limits bands from',
        default: null,
        help: 'Defaults to the first item with limits',
      },
    ],
  },
  VALUES: {
    category: 'Telemetry',
    label: 'Values',
    description: 'Table of items with status, limits bar and units',
    icon: 'mdi-table',
    component: ValuesPanel,
    content: ItemsConfig,
    defaults: { w: 4, h: 7 },
    keywords: ['ITEM', 'SETTING'],
    maxItems: null,
    options: [
      {
        name: 'LIMITS_BARS',
        type: 'boolean',
        label: 'Show limits bars',
        default: true,
      },
    ],
  },
  LIMITS: {
    category: 'Limits',
    label: 'Limits',
    description: 'Items currently out of limits, by target',
    icon: 'mdi-alert-outline',
    component: LimitsPanel,
    content: LimitsConfig,
    subtitle: (panel) =>
      panel.targets.length ? panel.targets.join(', ') : 'All targets',
    defaults: { w: 4, h: 6 },
    keywords: ['TARGET', 'SETTING'],
    maxItems: 0,
    options: [],
  },
  COMMAND: {
    category: 'Commanding',
    label: 'Command',
    description: 'Send a command with preset parameters, or run a script',
    icon: 'mdi-send-outline',
    component: CommandPanel,
    content: CommandConfig,
    title: (panel) =>
      panel.command?.commandName ||
      panel.script
        ?.split('/')
        .pop()
        .replace(/\.\w+$/, ''),
    subtitle: (panel) =>
      panel.script ||
      (panel.command &&
        `${panel.command.targetName} ${panel.command.commandName}`),
    validate: (panel) =>
      panel.command || panel.script ? null : 'Pick a command or script',
    defaults: { w: 4, h: 6 },
    keywords: ['COMMAND', 'SCRIPT', 'PARAMETER', 'SETTING'],
    maxItems: 0,
    options: [
      {
        name: 'DETAILS',
        type: 'text',
        label: 'Details',
        default: '',
        multiline: true,
        help: 'Shown in the panel above the button, e.g. what this does and when to use it',
      },
      {
        name: 'CONFIRM',
        type: 'select',
        label: 'Confirmation',
        default: 'HOLD',
        items: [
          { title: 'Hold to send', value: 'HOLD' },
          { title: 'Click to send', value: 'CLICK' },
        ],
        help: 'Hold takes 0.8 s, or 2 s when hazardous. Click asks for confirmation when hazardous.',
      },
      {
        name: 'OPEN_SCRIPT',
        type: 'boolean',
        label: 'Open Script Runner',
        help: 'Opens the running script in a new tab when it starts',
        default: false,
        when: (get, panel) => !!panel.script,
      },
    ],
  },
}

PANEL_TYPES[UNKNOWN_TYPE] = {
  label: 'Not installed',
  description: 'A panel type no installed plugin provides',
  icon: 'mdi-puzzle-remove-outline',
  component: UnknownPanel,
  content: null,
  hidden: true,
  defaults: { w: 4, h: 4 },
  keywords: [],
  maxItems: 0,
  options: [],
  subtitle: (panel) => `${panel.originalType} plugin not installed`,
}

// Built-in panel dialog editors a plugin can name as its `content`
export const CONTENT_EDITORS = {
  items: ItemsConfig,
  targets: LimitsConfig,
  command: CommandConfig,
}

// Add a panel type, e.g. from a plugin. Returns an error message, or null.
export function registerPanelType(type, definition) {
  const name = String(type || '').toUpperCase()
  if (!/^[A-Z][A-Z0-9_]*$/.test(name)) return `Invalid panel type '${type}'`
  if (PANEL_TYPES[name]) return `Panel type ${name} already exists`
  if (!definition?.component) return `Panel type ${name} has no component`
  const content =
    typeof definition.content === 'string'
      ? CONTENT_EDITORS[definition.content]
      : definition.content
  PANEL_TYPES[name] = {
    category: 'Plugins',
    icon: 'mdi-puzzle-outline',
    description: '',
    defaults: { w: 4, h: 4 },
    keywords: ['ITEM', 'ITEM_SETTING', 'SETTING'],
    maxItems: null,
    options: [],
    itemOptions: [],
    ...definition,
    label: definition.label || name,
    content: content ?? CONTENT_EDITORS.items,
  }
  return null
}

// Problem that keeps a panel from working, or null. Panels that show items
// need at least one; types can add their own check with `validate`.
export function panelProblem(panel) {
  const type = PANEL_TYPES[panel.type]
  if (type.keywords.includes('ITEM') && !panel.items.length) {
    return 'Add at least one item'
  }
  return type.validate?.(panel) ?? null
}
