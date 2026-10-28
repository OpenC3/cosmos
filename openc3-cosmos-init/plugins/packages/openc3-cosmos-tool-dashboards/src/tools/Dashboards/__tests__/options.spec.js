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
  itemOption,
  normalizeColor,
  option,
  settingsForType,
  validateItemOption,
  validateOption,
  visibleOptionDefs,
  withItemOption,
  withOption,
} from '../panels/options'

const stat = (settings = {}, itemSettings = {}) => ({
  type: 'STAT',
  settings,
  items: [
    {
      targetName: 'INST',
      packetName: 'HEALTH_STATUS',
      itemName: 'TEMP1',
      settings: itemSettings,
    },
  ],
})

describe('reading options', () => {
  it('returns the default when unset', () => {
    expect(option(stat(), 'GRAPH')).toBe(true)
  })

  it('decodes booleans, numbers and selects', () => {
    expect(option(stat({ GRAPH: ['off'] }), 'GRAPH')).toBe(false)
    const gauge = {
      type: 'GAUGE',
      settings: { MIN: ['-5'], LIMITS: ['custom'] },
    }
    expect(option(gauge, 'MIN')).toBe(-5)
    expect(option(gauge, 'LIMITS')).toBe('CUSTOM')
  })

  it('is undefined for options the type does not declare', () => {
    expect(option(stat(), 'NOPE')).toBeUndefined()
  })
})

describe('writing options', () => {
  it('encodes values for the file', () => {
    expect(withOption(stat(), 'GRAPH', false)).toEqual({ GRAPH: ['FALSE'] })
  })

  it('leaves defaults out of the file', () => {
    const panel = stat({ GRAPH: ['FALSE'] })
    expect(withOption(panel, 'GRAPH', true)).toEqual({})
    expect(withOption(panel, 'GRAPH', null)).toEqual({})
  })

  it('handles item options', () => {
    const panel = stat()
    const settings = withItemOption(panel, panel.items[0], 'COLOR', '#938bdb')
    expect(settings).toEqual({ COLOR: ['#938bdb'] })
    const colored = stat({}, settings)
    expect(itemOption(colored, colored.items[0], 'COLOR')).toBe('#938bdb')
    expect(withItemOption(colored, colored.items[0], 'COLOR', null)).toEqual({})
  })
})

describe('validation', () => {
  it('accepts valid values', () => {
    expect(validateOption('STAT', 'GRAPH', ['TRUE'])).toBeNull()
    expect(validateItemOption('STAT', 'COLOR', ['4dacff'])).toBeNull()
  })

  it('names the problem', () => {
    expect(validateOption('STAT', 'GRAPH', ['maybe'])).toMatch(
      /expects TRUE or FALSE/,
    )
    expect(validateOption('STAT', 'BOGUS', ['1'])).toMatch(
      /Unknown STAT SETTING 'BOGUS'/,
    )
    expect(validateItemOption('STAT', 'COLOR', ['blue'])).toMatch(
      /expects a color/,
    )
  })
})

describe('helpers', () => {
  it('normalizes colors and rejects anything else', () => {
    expect(normalizeColor('4DACFF')).toBe('#4dacff')
    expect(normalizeColor('#4dacff')).toBe('#4dacff')
    expect(normalizeColor('red')).toBeNull()
    expect(normalizeColor('javascript:alert(1)')).toBeNull()
  })

  it('hides options whose when() is false', () => {
    const names = (panel) => visibleOptionDefs(panel).map((def) => def.name)
    expect(names(stat())).toContain('LIMITS_LINES')
    expect(names(stat({ GRAPH: ['FALSE'] }))).not.toContain('LIMITS_LINES')
  })

  it('keeps only settings the new type understands', () => {
    expect(
      settingsForType({ GRAPH: ['FALSE'], PACKET_TIME: ['FALSE'] }, 'STATE'),
    ).toEqual({ PACKET_TIME: ['FALSE'] })
  })
})
