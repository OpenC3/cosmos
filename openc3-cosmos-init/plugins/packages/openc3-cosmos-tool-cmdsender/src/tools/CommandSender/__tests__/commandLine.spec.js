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
import { parseCmdLine } from '@openc3/vue-common/util'
import { formatCmd, formatFormCmd, formatKeyword } from '../commandLine'

const STATES = {
  NORMAL: { value: 0 },
  SPECIAL: { value: 1, hazardous: '' },
}

// CommandEditor rows as built for INST COLLECT
function collectRows() {
  return [
    { parameter_name: 'TYPE', val: 0, states: STATES, type: 'UINT' },
    { parameter_name: 'DURATION', val: '1.0', type: 'FLOAT' },
    { parameter_name: 'LABEL', val: "'abc'", type: 'STRING' },
  ]
}

describe('formatKeyword', () => {
  it('writes Ruby or Python keywords', () => {
    expect(formatKeyword('queue', '"Q1"')).toBe('queue: "Q1"')
    expect(formatKeyword('queue', '"Q1"', true)).toBe('queue="Q1"')
    expect(formatKeyword('validate', false)).toBe('validate: false')
    expect(formatKeyword('validate', false, true)).toBe('validate=False')
  })
})

describe('formatCmd', () => {
  it('writes a command without parameters', () => {
    const command = {
      target_name: 'INST',
      cmd_name: 'ABORT',
      cmd_params: {},
      obfuscated_items: [],
    }
    expect(formatCmd('cmd', command)).toBe('cmd("INST ABORT")')
  })

  it('quotes strings, masks obfuscated values and adds keywords', () => {
    const command = {
      target_name: 'INST',
      cmd_name: 'SET_PASSWORD',
      cmd_params: { USERNAME: 'bob', PASSWORD: 'secret', COUNT: 2 },
      obfuscated_items: ['PASSWORD'],
    }
    expect(
      formatCmd('cmd', command, {
        queueName: 'Q1',
        disableCommandValidation: true,
      }),
    ).toBe(
      `cmd("INST SET_PASSWORD with USERNAME 'bob', PASSWORD '*****', COUNT 2", queue: "Q1", validate: false)`,
    )
    expect(
      formatCmd('cmd', command, { queueName: false, python: true }),
    ).toContain('queue=False')
  })

  it('uses double quotes for strings with a single quote', () => {
    const command = {
      target_name: 'INST',
      cmd_name: 'SETPARAMS',
      cmd_params: { NAME: "it's" },
      obfuscated_items: [],
    }
    const line = formatCmd('cmd', command)
    expect(line).toBe(String.raw`cmd("INST SETPARAMS with NAME \"it's\"")`)
    expect(parseCmdLine(line).params).toEqual({ NAME: `"it's"` })
  })
})

describe('formatFormCmd', () => {
  it('writes the form as Send sends it', () => {
    expect(formatFormCmd('cmd', 'INST', 'COLLECT', collectRows())).toBe(
      `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 1, LABEL 'abc'")`,
    )
  })

  it('writes state values when conversions are disabled', () => {
    expect(
      formatFormCmd('cmd_raw', 'INST', 'COLLECT', collectRows(), {
        raw: true,
      }),
    ).toBe(`cmd_raw("INST COLLECT with TYPE 0, DURATION 1, LABEL 'abc'")`)
  })

  it('leaves off parameters without a value', () => {
    const rows = [
      { parameter_name: 'REQUIRED', val: null, type: 'UINT' },
      { parameter_name: 'UNSET', val: undefined, type: 'UINT' },
      { parameter_name: 'COUNT', val: '3', type: 'UINT' },
    ]
    expect(formatFormCmd('cmd', 'INST', 'X', rows)).toBe(
      'cmd("INST X with COUNT 3")',
    )
  })

  it('masks obfuscated values', () => {
    const rows = [
      { parameter_name: 'PASSWORD', val: "'secret'", type: 'STRING' },
    ]
    rows[0].obfuscate = true
    expect(formatFormCmd('cmd', 'INST', 'SET_PASSWORD', rows)).toBe(
      `cmd("INST SET_PASSWORD with PASSWORD '*****'")`,
    )
  })

  it('writes a value that cannot be converted as typed', () => {
    const rows = [{ parameter_name: 'ARRAY', val: '[1, 2,]', type: 'INT' }]
    expect(formatFormCmd('cmd', 'INST', 'ARRAYCMD', rows)).toBe(
      'cmd("INST ARRAYCMD with ARRAY [1, 2,]")',
    )
  })

  it('escapes arrays of strings so the line parses back', () => {
    const rows = [
      { parameter_name: 'NAMES', val: '["a", "b"]', type: 'STRING' },
    ]
    const line = formatFormCmd('cmd', 'INST', 'ARRAYCMD', rows)
    expect(line).toBe(
      String.raw`cmd("INST ARRAYCMD with NAMES [ \"a\", \"b\" ]")`,
    )
    expect(parseCmdLine(line).params).toEqual({ NAMES: '[ "a", "b" ]' })
  })

  it('round trips through parseCmdLine', () => {
    const line = formatFormCmd('cmd_no_range_check', 'INST', 'COLLECT', [
      ...collectRows(),
      { parameter_name: 'TEMP', val: '-1.5e3', type: 'FLOAT' },
      { parameter_name: 'BLOCK', val: '0xDEAD', type: 'BLOCK' },
    ])
    expect(parseCmdLine(line)).toMatchObject({
      method: 'cmd_no_range_check',
      target: 'INST',
      command: 'COLLECT',
      params: {
        TYPE: "'NORMAL'",
        DURATION: '1',
        LABEL: "'abc'",
        TEMP: '-1500',
        BLOCK: '0xDEAD',
      },
    })
  })

  it('writes BOOL values loaded from a command string as booleans', () => {
    const rows = [{ parameter_name: 'ITEM6', val: 'true', type: 'BOOL' }]
    expect(formatFormCmd('cmd', 'INST', 'JSONCMD', rows)).toBe(
      'cmd("INST JSONCMD with ITEM6 true")',
    )
  })

  it('writes a command with hundreds of parameters', () => {
    // Like the perf plugin's BIG target: 250 parameters with 32 states each
    const states = Object.fromEntries(
      Array.from({ length: 32 }, (_, i) => [`S${i}`, { value: i }]),
    )
    const rows = Array.from({ length: 250 }, (_, i) => ({
      parameter_name: `PARAM${i}`,
      val: i % 32,
      states,
      type: 'UINT',
    }))
    const line = formatFormCmd('cmd', 'BIG', 'CMD0', rows)
    const parsed = parseCmdLine(line)
    expect(Object.keys(parsed.params)).toHaveLength(250)
    expect(parsed.params.PARAM249).toBe(`'S${249 % 32}'`)
  })
})
