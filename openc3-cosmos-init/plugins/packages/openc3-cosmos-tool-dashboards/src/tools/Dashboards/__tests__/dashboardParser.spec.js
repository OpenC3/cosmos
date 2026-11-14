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

import { describe, expect, it } from 'vitest'
import {
  parseDashboard,
  parsePanel,
  serializeDashboard,
} from '../dashboardParser'
import { UNKNOWN_TYPE } from '../panels/registry'
import * as optionsModule from '../panels/options'

const TEXT = `DASHBOARD "INST Overview"
  COLUMNS 24
  SETTING POLLING_PERIOD 2

PANEL STAT 0 0 3 4 "Temperature 1"
  ITEM INST HEALTH_STATUS TEMP1
    ITEM_SETTING COLOR "#f6a25b"
  SETTING GRAPH FALSE
END

PANEL GRAPH 3 0 8 7 "Temperatures"
  ITEM INST HEALTH_STATUS TEMP1
  ITEM INST HEALTH_STATUS TEMP2 RAW
  SETTING THRESHOLDS INST HEALTH_STATUS TEMP1
END
`

describe('parseDashboard', () => {
  it('reads the title, grid, settings and panels', () => {
    const { model, errors } = parseDashboard(TEXT)
    expect(errors).toEqual([])
    expect(model.title).toBe('INST Overview')
    expect(model.columns).toBe(24)
    expect(model.settings).toEqual({ POLLING_PERIOD: ['2'] })
    expect(model.panels).toHaveLength(2)
    const [stat, graph] = model.panels
    expect(stat).toMatchObject({ type: 'STAT', x: 0, y: 0, w: 3, h: 4 })
    expect(stat.title).toBe('Temperature 1')
    expect(stat.items[0]).toMatchObject({
      targetName: 'INST',
      packetName: 'HEALTH_STATUS',
      itemName: 'TEMP1',
    })
    expect(stat.items[0].settings).toEqual({ COLOR: ['#f6a25b'] })
    expect(stat.settings).toEqual({ GRAPH: ['FALSE'] })
    expect(graph.items[1].valueType).toBe('RAW')
  })

  it('round trips through serializeDashboard', () => {
    const first = parseDashboard(TEXT).model
    const text = serializeDashboard(first)
    const second = parseDashboard(text)
    expect(second.errors).toEqual([])
    // uids are fresh on every parse
    const strip = (model) => ({
      ...model,
      panels: model.panels.map(({ uid: _uid, ...panel }) => panel),
    })
    expect(strip(second.model)).toEqual(strip(first))
    // and serializing again is stable
    expect(serializeDashboard(second.model)).toBe(text)
  })

  it('leaves the 12 column default out of the file', () => {
    const { model } = parseDashboard('DASHBOARD "Plain"\n')
    expect(model.columns).toBe(12)
    expect(serializeDashboard(model)).not.toMatch(/COLUMNS/)
  })

  it('reports errors with line numbers and keeps going', () => {
    const { model, errors } = parseDashboard(`DASHBOARD "Bad"

PANEL STAT 0 0 3 4
  ITEM INST HEALTH_STATUS TEMP1
  SETTING NOT_AN_OPTION 1
END

PANEL VALUES 3 0 3 4
  ITEM INST HEALTH_STATUS TEMP2
END
`)
    expect(errors.length).toBeGreaterThan(0)
    expect(errors[0].message).toMatch(/NOT_AN_OPTION/)
    expect(errors[0].lineNumber).toBe(5)
    expect(model.panels.some((panel) => panel.type === 'VALUES')).toBe(true)
  })

  it('rejects COLUMNS other than 12 or 24', () => {
    const { errors } = parseDashboard('DASHBOARD "Grid"\n  COLUMNS 10\n')
    expect(errors[0].message).toMatch(/COLUMNS must be/)
  })

  it('rejects keywords outside a panel', () => {
    const { errors } = parseDashboard(
      'DASHBOARD "Stray"\nITEM INST HEALTH_STATUS TEMP1\n',
    )
    expect(errors[0].message).toMatch(/inside a PANEL/)
  })

  it('validates option values', () => {
    const { errors } = parseDashboard(`DASHBOARD "Values"
PANEL STAT 0 0 3 4
  ITEM INST HEALTH_STATUS TEMP1
  SETTING GRAPH MAYBE
END
`)
    expect(errors[0].message).toMatch(/GRAPH expects TRUE or FALSE/)
  })

  it('keeps panels of types that are not installed, as written', () => {
    const text = `DASHBOARD "Plugins"

PANEL MAP 0 0 8 7 "Ground track"
  ITEM INST ADCS POSX
  SETTING COORDINATES ECEF
END
`
    const { model } = parseDashboard(text)
    const [panel] = model.panels
    expect(panel.type).toBe(UNKNOWN_TYPE)
    expect(panel.originalType).toBe('MAP')
    const saved = serializeDashboard(model)
    expect(saved).toContain('PANEL MAP 0 0 8 7 "Ground track"')
    expect(saved).toContain('  ITEM INST ADCS POSX')
    expect(saved).toContain('  SETTING COORDINATES ECEF')
  })
})

describe('parsePanel', () => {
  it('parses one block with line numbers relative to it', () => {
    const { model, errors } = parsePanel(
      'PANEL STAT 0 0 3 4\n  SETTING GRAPH MAYBE\nEND\n',
    )
    expect(model.type).toBe('STAT')
    expect(errors[0].lineNumber).toBe(2)
  })

  it('wants exactly one panel', () => {
    const { errors } = parsePanel('')
    expect(errors[0].message).toMatch(/Expected one PANEL/)
  })
})

describe('text settings', () => {
  it('round trips markdown with quotes, backslashes and line breaks', () => {
    const markdown =
      '## Don\'t "panic"\n\n- path `C:\\data\\new`\n- literal \\n stays\n# not a comment'
    // An empty TEXT panel parses, with a note to write some text
    const { model, errors } = parsePanel('PANEL TEXT 0 0 4 4\nEND\n')
    expect(errors.map((error) => error.message)).toEqual([
      'TEXT panel: Write some text',
    ])
    const { withOption, option } = optionsModule
    model.settings = withOption(model, 'TEXT', markdown)
    const text = serializeDashboard({
      title: 'T',
      columns: 12,
      settings: {},
      panels: [model],
    })
    // One line, in double quotes
    expect(
      text.split('\n').filter((line) => line.includes('SETTING TEXT')),
    ).toHaveLength(1)
    const reparsed = parseDashboard(text)
    expect(reparsed.errors).toEqual([])
    expect(option(reparsed.model.panels[0], 'TEXT')).toBe(markdown)
  })

  it('reads older text written in single quotes', () => {
    const { model, errors } = parsePanel(
      `PANEL COMMAND 0 0 4 4\n  COMMAND INST COLLECT\n  SETTING DETAILS 'Say "go"\\nthen wait'\nEND\n`,
    )
    expect(errors).toEqual([])
    expect(optionsModule.option(model, 'DETAILS')).toBe('Say "go"\nthen wait')
  })
})

describe('AGGREGATE panels', () => {
  it('reads statistics', () => {
    const { model, errors } = parsePanel(`PANEL AGGREGATE 0 0 4 4
  ITEM INST HEALTH_STATUS TEMP1
  SETTING STATS MIN MAX PERCENTILE
  SETTING PERCENTILE 99
END
`)
    expect(errors).toEqual([])
    expect(optionsModule.option(model, 'STATS')).toEqual([
      'MIN',
      'MAX',
      'PERCENTILE',
    ])
    expect(optionsModule.option(model, 'PERCENTILE')).toBe(99)
  })

  it('reports unknown statistics', () => {
    const { errors } = parsePanel(`PANEL AGGREGATE 0 0 4 4
  ITEM INST HEALTH_STATUS TEMP1
  SETTING STATS MIN CUSTOM
END
`)
    expect(errors.map((error) => error.message)).toEqual([
      expect.stringContaining("doesn't know CUSTOM"),
    ])
  })
})
