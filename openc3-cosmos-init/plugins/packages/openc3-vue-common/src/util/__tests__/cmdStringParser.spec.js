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
  paramValueFromText,
  parseCmdLine,
  parseCmdText,
  parseCmdTextLenient,
} from '../cmdStringParser'

describe('parseCmdText', () => {
  it('parses a command without parameters', () => {
    expect(parseCmdText('INST ABORT')).toEqual({
      target: 'INST',
      command: 'ABORT',
      params: {},
    })
  })

  it('keeps the raw text of each value', () => {
    expect(
      parseCmdText(
        "INST COLLECT with TYPE 'NORMAL', DURATION 1.5, OPCODE 0xAB, TEMP -10",
      ).params,
    ).toEqual({
      TYPE: "'NORMAL'",
      DURATION: '1.5',
      OPCODE: '0xAB',
      TEMP: '-10',
    })
  })

  it('keeps commas and spaces inside quoted strings', () => {
    expect(
      parseCmdText(`INST SETPARAMS with A 'hello, world', B "x, y", C 1`)
        .params,
    ).toEqual({ A: "'hello, world'", B: '"x, y"', C: '1' })
  })

  it('keeps commas inside arrays, including one level of nesting', () => {
    expect(
      parseCmdText('INST ARRAY with A [1, 2, 3], B [[1, 2], [3]], C 4').params,
    ).toEqual({ A: '[1, 2, 3]', B: '[[1, 2], [3]]', C: '4' })
  })

  it('accepts any case for with and loose whitespace around commas', () => {
    expect(parseCmdText('  INST   COLLECT  WITH TYPE 0 ,DURATION 1  ')).toEqual(
      {
        target: 'INST',
        command: 'COLLECT',
        params: { TYPE: '0', DURATION: '1' },
      },
    )
  })

  it('allows a trailing comma, as the server does', () => {
    expect(
      parseCmdText('INST COLLECT with TYPE 0, DURATION 1,').params,
    ).toEqual({ TYPE: '0', DURATION: '1' })
  })

  it('keeps the case of names as given', () => {
    expect(parseCmdText('inst collect with type 0')).toEqual({
      target: 'inst',
      command: 'collect',
      params: { type: '0' },
    })
  })

  it.each([
    ['', /empty/],
    ['INST', /Target Name and Command Name/],
    ['INST COLLECT NOW', /Only Target Name and Command Name/],
    ['INST COLLECT with', /must be followed by parameters/],
    ['INST COLLECT with TYPE', /Missing value/],
    ['INST COLLECT with TYPE 0 DURATION 1', /Missing comma/],
    ['INST COLLECT with TYPE, DURATION 1', /Missing value for TYPE/],
    ['INST COLLECT with , TYPE 0', /Missing command parameter before comma/],
  ])('rejects %j', (text, error) => {
    expect(() => parseCmdText(text)).toThrow(error)
  })
})

describe('parseCmdLine', () => {
  it('parses bare command text with no method', () => {
    expect(parseCmdLine('INST COLLECT with TYPE 0')).toEqual({
      method: null,
      target: 'INST',
      command: 'COLLECT',
      params: { TYPE: '0' },
      queue: undefined,
      validate: undefined,
      ignored: [],
    })
  })

  it('unwraps cmd("...")', () => {
    expect(parseCmdLine(`cmd("INST COLLECT with TYPE 'NORMAL'")`)).toEqual({
      method: 'cmd',
      target: 'INST',
      command: 'COLLECT',
      params: { TYPE: "'NORMAL'" },
      queue: undefined,
      validate: undefined,
      ignored: [],
    })
  })

  it('unwraps single quoted strings', () => {
    expect(
      parseCmdLine(`cmd('INST COLLECT with TYPE "NORMAL"')`).params,
    ).toEqual({ TYPE: '"NORMAL"' })
  })

  it('unescapes quotes inside the string', () => {
    expect(parseCmdLine(`cmd("INST SET with A \\"x\\"")`).params).toEqual({
      A: '"x"',
    })
  })

  it.each([
    'cmd_raw',
    'cmd_no_range_check',
    'cmd_no_hazardous_check',
    'cmd_no_checks',
    'cmd_raw_no_range_check',
    'cmd_raw_no_hazardous_check',
    'cmd_raw_no_checks',
  ])('reports the %s method', (method) => {
    expect(parseCmdLine(`${method}("INST ABORT")`).method).toBe(method)
  })

  it('tolerates whitespace and a trailing semicolon', () => {
    const parsed = parseCmdLine('  cmd ( "INST ABORT" ) ; ')
    expect(parsed.method).toBe('cmd')
    expect(parsed.command).toBe('ABORT')
  })

  it.each([
    ['Ruby', `cmd("INST ABORT", queue: "Q1", validate: false)`],
    ['Python', `cmd("INST ABORT", queue="Q1", validate=False)`],
    ['Python spaced', `cmd("INST ABORT", queue = 'Q1', validate = False)`],
  ])('reads %s queue and validate keywords', (_lang, line) => {
    const parsed = parseCmdLine(line)
    expect(parsed.queue).toBe('Q1')
    expect(parsed.validate).toBe(false)
  })

  it('reads queue false and validate true', () => {
    const parsed = parseCmdLine(
      `cmd("INST ABORT", queue: false, validate=True)`,
    )
    expect(parsed.queue).toBe(false)
    expect(parsed.validate).toBe(true)
  })

  it.each(['queue: nil', 'queue=None'])('reads %s as no queue', (keyword) => {
    const parsed = parseCmdLine(`cmd("INST ABORT", ${keyword})`)
    expect(parsed.queue).toBeUndefined()
    expect(parsed.ignored).toEqual([])
  })

  it('ignores a trailing comment after the call', () => {
    const parsed = parseCmdLine(`cmd("INST SET with A 'x # y'")  # a comment`)
    expect(parsed.params).toEqual({ A: "'x # y'" })
  })

  it('ignores a trailing comment with parentheses after the call', () => {
    const parsed = parseCmdLine(
      `cmd("INST COLLECT with TYPE 'NORMAL'", queue: "Q") # collect (normal)`,
    )
    expect(parsed.params).toEqual({ TYPE: "'NORMAL'" })
    expect(parsed.queue).toBe('Q')
  })

  it('reads a Ruby call without parentheses', () => {
    const parsed = parseCmdLine(
      `cmd_no_range_check "INST COLLECT with TYPE 'NORMAL', DURATION 2", queue: "Q" # note`,
    )
    expect(parsed.method).toBe('cmd_no_range_check')
    expect(parsed.params).toEqual({ TYPE: "'NORMAL'", DURATION: '2' })
    expect(parsed.queue).toBe('Q')
  })

  it('reads bare text that starts with a quoted word as command text', () => {
    expect(() => parseCmdLine(`INST "ABORT"`)).not.toThrow(/method/)
  })

  it('reads a Ruby call without parentheses or a comment', () => {
    const parsed = parseCmdLine(`cmd "INST ABORT", queue: "Q"`)
    expect(parsed.command).toBe('ABORT')
    expect(parsed.queue).toBe('Q')
  })

  it('keeps escaped quotes and # in a Ruby call without parentheses', () => {
    const parsed = parseCmdLine(
      `cmd "INST SET with A 'say \\"#1\\"'" # a comment`,
    )
    expect(parsed.params).toEqual({ A: `'say "#1"'` })
  })

  it('reads an unquoted queue name', () => {
    expect(parseCmdLine('cmd("INST ABORT", queue: Q1)').queue).toBe('Q1')
  })

  it('keeps escapes other than quotes and backslashes as written', () => {
    expect(parseCmdLine(`cmd("INST SET with A 'a\\nb'")`).params).toEqual({
      A: "'a\\nb'",
    })
  })

  it('keeps escaped quotes in a keyword value', () => {
    expect(parseCmdLine(`cmd("INST ABORT", queue: "Q\\"1")`).queue).toBe(
      'Q\\"1',
    )
  })

  it('lists other keywords as ignored', () => {
    const parsed = parseCmdLine(
      `cmd("INST ABORT", timeout: 5, log_message: false)`,
    )
    expect(parsed.ignored).toEqual(['timeout', 'log_message'])
  })

  it('keeps commas in the command string apart from keywords', () => {
    const parsed = parseCmdLine(
      `cmd("INST SET with A 'x, queue: y', B 1", queue: "Q")`,
    )
    expect(parsed.params).toEqual({ A: "'x, queue: y'", B: '1' })
    expect(parsed.queue).toBe('Q')
  })

  it.each([
    ['tlm("INST HEALTH_STATUS TEMP1")', /Unknown command method tlm/],
    ['cmd()', /single string/],
    ['cmd(INST ABORT)', /single string/],
    ['cmd("INST", "ABORT")', /single string/],
    [`cmd("INST COLLECT", {"TYPE" => 0})`, /single string/],
    ['cmd("INST ABORT"', /Unterminated|closing/],
    ['cmd("INST ABORT)', /Unterminated/],
    ['cmd("INST ABORT", queue: )', /Invalid keyword/],
    ['cmd("INST ABORT", validate: maybe)', /validate must be true or false/],
    ['cmd("INST ABORT\\)', /Unterminated string/],
    ['cmd_raw "INST ABORT', /Unterminated string/],
    ['cmd("INST ABORT" extra)', /single string/],
  ])('rejects %j', (line, error) => {
    expect(() => parseCmdLine(line)).toThrow(error)
  })
})

describe('parseCmdTextLenient', () => {
  it('parses valid command text strictly', () => {
    expect(
      parseCmdTextLenient(`INST SET with A 'hello, world', B 1`).params,
    ).toEqual({ A: "'hello, world'", B: '1' })
  })

  it('reads unquoted values with spaces, as CommandQueue writes them', () => {
    expect(
      parseCmdTextLenient('INST SETPARAMS with LABEL hello world, VALUE1 1'),
    ).toEqual({
      target: 'INST',
      command: 'SETPARAMS',
      params: { LABEL: 'hello world', VALUE1: '1' },
    })
  })

  it('keeps commas inside arrays', () => {
    expect(
      parseCmdTextLenient('INST ARY with ARRAY [1, 2], LABEL a b').params,
    ).toEqual({ ARRAY: '[1, 2]', LABEL: 'a b' })
  })

  it('returns null for text that is not a command', () => {
    expect(parseCmdTextLenient('INST')).toBeNull()
    expect(parseCmdTextLenient('')).toBeNull()
    expect(parseCmdTextLenient('INST COLLECT NOW')).toBeNull()
  })

  it('skips a parameter without a value', () => {
    expect(
      parseCmdTextLenient('INST SETPARAMS with LABEL a b, ORPHAN').params,
    ).toEqual({ LABEL: 'a b' })
  })
})

describe('paramValueFromText', () => {
  const states = {
    NORMAL: { value: 0 },
    SPECIAL: { value: 1, hazardous: '' },
  }

  it('selects a state by name, quoted or not, in any case', () => {
    expect(paramValueFromText({ states, type: 'UINT' }, "'SPECIAL'")).toBe(1)
    expect(paramValueFromText({ states, type: 'UINT' }, 'normal')).toBe(0)
  })

  it('selects a state by its raw value', () => {
    expect(paramValueFromText({ states, type: 'UINT' }, '1')).toBe(1)
    expect(paramValueFromText({ states, type: 'UINT' }, '0x1')).toBe(1)
  })

  it('keeps a value that is not a state, e.g. manually entered', () => {
    expect(paramValueFromText({ states, type: 'UINT' }, '7')).toBe('7')
  })

  it('quotes strings so they stay strings', () => {
    expect(paramValueFromText({ type: 'STRING' }, '123')).toBe("'123'")
    expect(paramValueFromText({ type: 'STRING' }, "'abc'")).toBe("'abc'")
    expect(paramValueFromText({ type: 'BLOCK' }, '0xABCD')).toBe('0xABCD')
  })

  it('keeps other values as written', () => {
    expect(paramValueFromText({ type: 'UINT' }, '0x10')).toBe('0x10')
    expect(paramValueFromText({ type: 'FLOAT' }, '1.5e3')).toBe('1.5e3')
  })

  it('keeps arrays as arrays, including arrays of strings', () => {
    expect(paramValueFromText({ type: 'STRING' }, '[ "alpha", "beta" ]')).toBe(
      '[ "alpha", "beta" ]',
    )
    expect(paramValueFromText({ type: 'FLOAT' }, '[1, 2]')).toBe('[1, 2]')
  })
})
