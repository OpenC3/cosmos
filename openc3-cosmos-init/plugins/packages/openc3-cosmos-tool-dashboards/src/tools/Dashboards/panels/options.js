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

// Panel options. Each panel type declares its options in panels/registry.js:
//
//   { name: 'GRAPH', type: 'boolean', label: 'Show graph', default: true }
//
// and the file format, parser validation, panel dialog controls and typed
// reads all come from that declaration. In a dashboard file an option is
//
//   SETTING <NAME> <values...>
//
// and is only written when it differs from the default. Items can have
// options too, declared as `itemOptions` and written after their ITEM line:
//
//   ITEM INST HEALTH_STATUS TEMP1
//     ITEM_SETTING COLOR "#d95926"
//
// Optional fields:
//   help        caption under the control
//   when        (get, panel) => boolean, hides the option when it doesn't
//               apply; get(NAME) reads another option of the same panel
//   items       select choices, [{ title, value }]
//   min / max / unit   number limits and suffix
//   multiline   text options edited in a text area
//
// To add an option type, add an entry to OPTION_TYPES (decode the SETTING
// values, encode a value back, validate) and a control in OptionsEditor.vue
// (or ItemOptionsEditor.vue for item options).

import { PANEL_TYPES } from './registry'

const TRUE_WORDS = ['TRUE', 'ON', 'YES']
const FALSE_WORDS = ['FALSE', 'OFF', 'NO']

function normalizeColor(value) {
  const match = /^#?([0-9a-f]{6})$/i.exec(String(value).trim())
  return match ? `#${match[1].toLowerCase()}` : null
}

const OPTION_TYPES = {
  boolean: {
    decode: (values) => TRUE_WORDS.includes(String(values[0]).toUpperCase()),
    encode: (value) => [value ? 'TRUE' : 'FALSE'],
    validate: (values) =>
      values.length === 1 &&
      [...TRUE_WORDS, ...FALSE_WORDS].includes(String(values[0]).toUpperCase())
        ? null
        : 'expects TRUE or FALSE',
  },
  select: {
    decode: (values) => String(values[0]).toUpperCase(),
    encode: (value) => [value],
    validate: (values, def) => {
      const allowed = def.items.map((item) => String(item.value).toUpperCase())
      return values.length === 1 &&
        allowed.includes(String(values[0]).toUpperCase())
        ? null
        : `expects one of ${allowed.join(', ')}`
    },
  },
  number: {
    decode: (values) => Number(values[0]),
    encode: (value) => [String(value)],
    validate: (values, def) => {
      const number = Number(values[0])
      if (values.length !== 1 || !Number.isFinite(number)) {
        return 'expects a number'
      }
      if (def.min !== undefined && number < def.min) {
        return `must be at least ${def.min}`
      }
      if (def.max !== undefined && number > def.max) {
        return `must be at most ${def.max}`
      }
      return null
    },
  },
  // Free text, written quoted: SETTING DETAILS "Starts a collect". Line
  // breaks are written as \n so the setting stays on one line.
  text: {
    decode: (values) => values.join(' ').replace(/\\n/g, '\n'),
    encode: (value) => [String(value).replace(/\r?\n/g, '\\n')],
    validate: (values) => (values.length ? null : 'expects some text'),
  },
  // rrggbb. A bare # starts a comment in dashboard files, so colors are
  // written quoted ("#3987e5") or without the # (3987e5)
  color: {
    decode: (values) => normalizeColor(values[0]),
    encode: (value) => [value],
    validate: (values) =>
      values.length === 1 && normalizeColor(values[0])
        ? null
        : 'expects a color like 3987e5 or "#3987e5" (a bare # starts a comment)',
  },
  // A telemetry item: SETTING NAME <TARGET> <PACKET> <ITEM>
  item: {
    decode: (values) => ({
      targetName: values[0].toUpperCase(),
      packetName: values[1].toUpperCase(),
      itemName: values[2].toUpperCase(),
    }),
    encode: (value) => [value.targetName, value.packetName, value.itemName],
    validate: (values) =>
      values.length === 3 ? null : 'expects <Target> <Packet> <Item>',
  },
}

// Generic codec over a list of declarations and a settings object
// ({ NAME: [values...] }). Panels and items both use these.

function find(defs, name) {
  return defs.find((def) => def.name === name)
}

function read(defs, settings, name) {
  const def = find(defs, name)
  if (!def) return undefined
  const values = settings?.[name]
  if (!values || values.length === 0) return def.default ?? null
  return OPTION_TYPES[def.type].decode(values, def)
}

// New settings with one value changed; defaults are removed so files only
// list what was customized
function write(defs, settings, name, value) {
  const def = find(defs, name)
  const result = { ...settings }
  const isDefault =
    value === null ||
    value === undefined ||
    value === '' ||
    JSON.stringify(value) === JSON.stringify(def.default ?? null)
  if (isDefault) {
    delete result[name]
  } else {
    result[name] = OPTION_TYPES[def.type].encode(value, def)
  }
  return result
}

function validate(defs, keyword, owner, name, values) {
  const def = find(defs, name)
  if (!def) {
    const names = defs.map((d) => d.name).join(', ') || 'none'
    return `Unknown ${owner} ${keyword} '${name}'. Known: ${names}`
  }
  const error = OPTION_TYPES[def.type].validate(values, def)
  return error ? `${keyword} ${name} ${error}` : null
}

// Panel options (SETTING)

export function optionDefs(type) {
  return PANEL_TYPES[type]?.options || []
}

export function option(panel, name) {
  return read(optionDefs(panel.type), panel.settings, name)
}

export function withOption(panel, name, value) {
  return write(optionDefs(panel.type), panel.settings, name, value)
}

export function validateOption(type, name, values) {
  return validate(optionDefs(type), 'SETTING', type, name, values)
}

// Options shown for a panel, after each declaration's `when`
export function visibleOptionDefs(panel) {
  const get = (name) => option(panel, name)
  return optionDefs(panel.type).filter(
    (def) => !def.when || def.when(get, panel),
  )
}

// Settings that still apply after changing a panel to another type
export function settingsForType(settings, type) {
  const defs = optionDefs(type)
  return Object.fromEntries(
    Object.entries(settings || {}).filter(([name]) => find(defs, name)),
  )
}

// Item options (ITEM_SETTING)

export function itemOptionDefs(type) {
  return PANEL_TYPES[type]?.itemOptions || []
}

export function itemOption(panel, item, name) {
  return read(itemOptionDefs(panel.type), item.settings, name)
}

export function withItemOption(panel, item, name, value) {
  return write(itemOptionDefs(panel.type), item.settings, name, value)
}

export function validateItemOption(type, name, values) {
  return validate(itemOptionDefs(type), 'ITEM_SETTING', type, name, values)
}
