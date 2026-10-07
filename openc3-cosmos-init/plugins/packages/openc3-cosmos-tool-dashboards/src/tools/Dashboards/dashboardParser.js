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

// Parses and serializes the DASHBOARD text format:
//
//   DASHBOARD "INST Overview"
//     SETTING POLLING_PERIOD 1
//   PANEL GRAPH 0 3 8 7 "Temperatures"
//     ITEM INST HEALTH_STATUS TEMP1
//     ITEM INST2 HEALTH_STATUS TEMP1
//     SETTING DURATION 120
//   END
//
// PANEL <TYPE> <Column> <Row> <Width> <Height> [Title] places a panel on the
// 12 column grid. Column and row are 0 based, height is in grid rows. The
// keywords a panel accepts come from its entry in panels/registry.js.

import {
  ConfigParserError,
  ConfigParserService,
} from '@openc3/js-common/services'
import { PANEL_TYPES, UNKNOWN_TYPE, panelProblem } from './panels/registry'
import { GRID_COLUMNS, MAX_H } from './layout'
import { validateItemOption, validateOption } from './panels/options'

export const VALUE_TYPES = ['RAW', 'CONVERTED', 'FORMATTED', 'WITH_UNITS']

// First line of every saved dashboard. Comments aren't kept by the parser, so
// writing it on every save keeps exactly one copy at the top.
const BETA_NOTICE =
  '# Dashboards is a beta feature: this file format can change in any release'

const USAGE = {
  DASHBOARD: 'DASHBOARD <Title>',
  PANEL: 'PANEL <Type> <Column> <Row> <Width> <Height> [Title]',
  ITEM: 'ITEM <Target> <Packet> <Item> [Value Type]',
  ITEM_SETTING: 'ITEM_SETTING <Name> [Values...] (applies to the ITEM above)',
  TARGET: 'TARGET <Target>',
  COMMAND: 'COMMAND <Target> <Command>',
  SCRIPT: 'SCRIPT <Script file, e.g. INST/procedures/collect.rb>',
  PARAMETER: 'PARAMETER <Parameter> <Value>',
  SETTING: 'SETTING <Name> [Values...]',
  END: 'END',
}

let nextUid = 1
export function panelUid() {
  return nextUid++
}

export function emptyDashboard(title = 'New Dashboard') {
  return { title, settings: {}, panels: [] }
}

export function newPanel(type, x, y, w, h, title = '') {
  return {
    uid: panelUid(),
    type,
    x,
    y,
    w,
    h,
    title,
    items: [],
    targets: [],
    command: null,
    script: null,
    parameters: {},
    settings: {},
  }
}

// The panel field each content keyword fills, and its empty value
const KEYWORD_FIELDS = {
  ITEM: ['items', () => []],
  TARGET: ['targets', () => []],
  COMMAND: ['command', () => null],
  SCRIPT: ['script', () => null],
  PARAMETER: ['parameters', () => ({})],
}

// Changes that clear what a panel type doesn't use, for switching a panel to
// `type` without carrying over (and later writing out) fields it can't have
export function clearedFieldsFor(type) {
  const keywords = PANEL_TYPES[type].keywords
  return Object.fromEntries(
    Object.entries(KEYWORD_FIELDS)
      .filter(([keyword]) => !keywords.includes(keyword))
      .map(([, [field, empty]]) => [field, empty()]),
  )
}

function toInt(parser, value, name, usage, min, max) {
  const number = Number(value)
  if (!Number.isInteger(number) || number < min || number > max) {
    throw new ConfigParserError(
      parser,
      `${name} must be an integer from ${min} to ${max}, got '${value}'`,
      usage,
    )
  }
  return number
}

export function parseDashboard(text) {
  const parser = new ConfigParserService()
  const model = emptyDashboard('')
  const errors = []
  let panel = null

  const requireKeyword = (keyword) => {
    if (!panel) {
      throw new ConfigParserError(
        parser,
        `${keyword} must be inside a PANEL ... END block`,
        USAGE[keyword],
      )
    }
    const definition = PANEL_TYPES[panel.type]
    if (!definition.keywords.includes(keyword)) {
      throw new ConfigParserError(
        parser,
        `${keyword} is not used by ${panel.type} panels. Allowed: ${definition.keywords.join(', ')}`,
        USAGE[keyword],
      )
    }
  }

  parser.parse_string(text, '', false, true, (keyword, parameters, line) => {
    try {
      // A panel whose type isn't installed keeps its lines as written
      if (panel?.type === UNKNOWN_TYPE && keyword !== 'END') {
        panel.raw.push(line)
        return
      }
      switch (keyword) {
        case 'DASHBOARD':
          parser.verify_num_parameters(1, 1, USAGE.DASHBOARD)
          model.title = parameters[0]
          break
        case 'PANEL': {
          parser.verify_num_parameters(5, 6, USAGE.PANEL)
          if (panel) {
            throw new ConfigParserError(
              parser,
              `PANEL started before END of the previous panel (line ${panel.lineNumber})`,
              USAGE.PANEL,
            )
          }
          const type = parameters[0].toUpperCase()
          const known = !!PANEL_TYPES[type] && type !== UNKNOWN_TYPE
          const x = toInt(
            parser,
            parameters[1],
            'Column',
            USAGE.PANEL,
            0,
            GRID_COLUMNS - 1,
          )
          const w = toInt(
            parser,
            parameters[3],
            'Width',
            USAGE.PANEL,
            1,
            GRID_COLUMNS,
          )
          panel = newPanel(
            known ? type : UNKNOWN_TYPE,
            x,
            toInt(parser, parameters[2], 'Row', USAGE.PANEL, 0, 1000),
            Math.min(w, GRID_COLUMNS - x),
            // Taller than the screen is clamped, like width past the grid
            Math.min(
              toInt(parser, parameters[4], 'Height', USAGE.PANEL, 1, 100),
              MAX_H,
            ),
            parameters[5] || '',
          )
          panel.lineNumber = parser.lineNumber
          if (!known) {
            // Usually a panel from a plugin that isn't installed here. Keep
            // it so saving doesn't drop it, and say so.
            panel.originalType = type
            panel.raw = []
            throw new ConfigParserError(
              parser,
              `Panel type '${parameters[0]}' isn't installed (a plugin may be missing); the panel is kept as written`,
              USAGE.PANEL,
            )
          }
          break
        }
        case 'END':
          parser.verify_num_parameters(0, 0, USAGE.END)
          if (!panel) {
            throw new ConfigParserError(
              parser,
              'END without a PANEL',
              USAGE.END,
            )
          }
          delete panel.lineNumber
          model.panels.push(panel)
          {
            // Keep incomplete panels, but say what's missing
            const problem = panelProblem(panel)
            const type = panel.type
            panel = null
            if (problem) {
              throw new ConfigParserError(
                parser,
                `${type} panel: ${problem}`,
                '',
              )
            }
          }
          break
        case 'ITEM': {
          requireKeyword(keyword)
          parser.verify_num_parameters(3, 4, USAGE.ITEM)
          const valueType = (parameters[3] || 'CONVERTED').toUpperCase()
          if (!VALUE_TYPES.includes(valueType)) {
            throw new ConfigParserError(
              parser,
              `Unknown value type '${parameters[3]}'. Types: ${VALUE_TYPES.join(', ')}`,
              USAGE.ITEM,
            )
          }
          const max = PANEL_TYPES[panel.type].maxItems
          if (max && panel.items.length >= max) {
            throw new ConfigParserError(
              parser,
              `${panel.type} panels show ${max} item${max === 1 ? '' : 's'}`,
              USAGE.ITEM,
            )
          }
          panel.items.push({
            targetName: parameters[0].toUpperCase(),
            packetName: parameters[1].toUpperCase(),
            itemName: parameters[2].toUpperCase(),
            valueType,
            settings: {},
          })
          break
        }
        case 'ITEM_SETTING': {
          requireKeyword(keyword)
          parser.verify_num_parameters(1, null, USAGE.ITEM_SETTING)
          const item = panel.items.at(-1)
          if (!item) {
            throw new ConfigParserError(
              parser,
              'ITEM_SETTING must follow an ITEM',
              USAGE.ITEM_SETTING,
            )
          }
          const name = parameters[0].toUpperCase()
          const values = parameters.slice(1)
          const error = validateItemOption(panel.type, name, values)
          if (error)
            throw new ConfigParserError(parser, error, USAGE.ITEM_SETTING)
          item.settings[name] = values
          break
        }
        case 'TARGET':
          requireKeyword(keyword)
          parser.verify_num_parameters(1, 1, USAGE.TARGET)
          panel.targets.push(parameters[0].toUpperCase())
          break
        case 'COMMAND':
          requireKeyword(keyword)
          parser.verify_num_parameters(2, 2, USAGE.COMMAND)
          panel.command = {
            targetName: parameters[0].toUpperCase(),
            commandName: parameters[1].toUpperCase(),
          }
          break
        case 'SCRIPT':
          requireKeyword(keyword)
          parser.verify_num_parameters(1, 1, USAGE.SCRIPT)
          panel.script = parameters[0]
          break
        case 'PARAMETER':
          requireKeyword(keyword)
          parser.verify_num_parameters(2, 2, USAGE.PARAMETER)
          panel.parameters[parameters[0].toUpperCase()] = parameters[1]
          break
        case 'SETTING': {
          parser.verify_num_parameters(1, null, USAGE.SETTING)
          const name = parameters[0].toUpperCase()
          if (panel) {
            const values = parameters.slice(1)
            const error = validateOption(panel.type, name, values)
            if (error) {
              throw new ConfigParserError(parser, error, USAGE.SETTING)
            }
            panel.settings[name] = values
          } else {
            model.settings[name] = parameters.slice(1)
          }
          break
        }
        default:
          throw new ConfigParserError(
            parser,
            `Unknown keyword '${keyword}'`,
            '',
          )
      }
    } catch (error) {
      if (!(error instanceof ConfigParserError)) throw error
      errors.push({
        message: error.message,
        usage: error.usage,
        line: error.line,
        lineNumber: error.lineNumber,
      })
    }
  })
  if (panel) {
    errors.push({
      message: `PANEL on line ${panel.lineNumber} is missing its END`,
      usage: USAGE.END,
      line: '',
      lineNumber: panel.lineNumber,
    })
    delete panel.lineNumber
    model.panels.push(panel)
  }
  return { model, errors }
}

// Titles always read as text, even single words
function quoteTitle(value) {
  const string = String(value)
  return string.includes('"') ? `'${string}'` : `"${string}"`
}

function quote(value) {
  const string = String(value)
  if (string === '' || /[\s#]/.test(string)) {
    return string.includes('"') ? `'${string}'` : `"${string}"`
  }
  return string
}

// PANEL ... END lines for one panel
function panelLines(panel) {
  const lines = []
  if (panel.type === UNKNOWN_TYPE) {
    let header = `PANEL ${panel.originalType} ${panel.x} ${panel.y} ${panel.w} ${panel.h}`
    if (panel.title) header += ` ${quoteTitle(panel.title)}`
    return [header, ...panel.raw.map((line) => `  ${line}`), 'END']
  }
  let header = `PANEL ${panel.type} ${panel.x} ${panel.y} ${panel.w} ${panel.h}`
  if (panel.title) header += ` ${quoteTitle(panel.title)}`
  lines.push(header)
  // Only what this type allows, so a field left over from another type can't
  // produce a file the parser rejects
  const allowed = new Set(PANEL_TYPES[panel.type].keywords)
  if (allowed.has('COMMAND') && panel.command) {
    lines.push(
      `  COMMAND ${panel.command.targetName} ${panel.command.commandName}`,
    )
  }
  if (allowed.has('SCRIPT') && panel.script) {
    lines.push(`  SCRIPT ${quote(panel.script)}`)
  }
  if (allowed.has('PARAMETER')) {
    for (const [name, value] of Object.entries(panel.parameters || {})) {
      lines.push(`  PARAMETER ${name} ${quote(value)}`)
    }
  }
  if (allowed.has('TARGET')) {
    for (const target of panel.targets || []) {
      lines.push(`  TARGET ${target}`)
    }
  }
  if (allowed.has('ITEM')) {
    for (const item of panel.items || []) {
      let line = `  ITEM ${item.targetName} ${item.packetName} ${item.itemName}`
      if (item.valueType && item.valueType !== 'CONVERTED') {
        line += ` ${item.valueType}`
      }
      lines.push(line)
      for (const [name, values] of Object.entries(item.settings || {})) {
        lines.push(`    ITEM_SETTING ${[name, ...values].map(quote).join(' ')}`)
      }
    }
  }
  for (const [name, values] of Object.entries(panel.settings || {})) {
    lines.push(`  SETTING ${[name, ...values].map(quote).join(' ')}`)
  }
  lines.push('END')
  return lines
}

export function serializeDashboard(model) {
  const lines = [
    BETA_NOTICE,
    `DASHBOARD ${quoteTitle(model.title || 'Dashboard')}`,
  ]
  for (const [name, values] of Object.entries(model.settings || {})) {
    lines.push(`  SETTING ${[name, ...values].map(quote).join(' ')}`)
  }
  const panels = [...model.panels].sort((a, b) => a.y - b.y || a.x - b.x)
  for (const panel of panels) {
    lines.push('', ...panelLines(panel))
  }
  return lines.join('\n') + '\n'
}

// One panel's code, as shown in the panel dialog
export function serializePanel(panel) {
  return panelLines(panel).join('\n') + '\n'
}

// Parse one PANEL ... END block. Returns { model: panel, errors } with line
// numbers relative to the block.
export function parsePanel(text) {
  const { model, errors } = parseDashboard(`DASHBOARD "Panel"\n${text}`)
  const shifted = errors.map((error) => ({
    ...error,
    lineNumber: error.lineNumber - 1,
  }))
  if (!shifted.length && model.panels.length !== 1) {
    shifted.push({
      message: `Expected one PANEL ... END block, found ${model.panels.length}`,
      usage: USAGE.PANEL,
      line: '',
      lineNumber: 1,
    })
  }
  return { model: model.panels[0] || null, errors: shifted }
}

// Re-parsed text gets fresh panels. Carry over the uids of panels that are
// still the same type in the same position so they don't remount (and
// restart their subscriptions) on every keystroke in the code view or undo.
export function reuseUids(previous, panels) {
  const sorted = [...previous].sort((a, b) => a.y - b.y || a.x - b.x)
  const used = new Set()
  for (const panel of panels) {
    const match =
      previous.find(
        (old) =>
          !used.has(old.uid) &&
          old.type === panel.type &&
          old.x === panel.x &&
          old.y === panel.y,
      ) || sorted.find((old) => !used.has(old.uid) && old.type === panel.type)
    if (match) {
      panel.uid = match.uid
      used.add(match.uid)
    }
  }
  return panels
}
