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
import { convertToValue } from '../cmdUtilities'
import { paramValueFromText } from '../cmdStringParser'

describe('convertToValue', () => {
  it('converts true and false for BOOL parameters', () => {
    expect(convertToValue({ val: 'true', type: 'BOOL' })).toBe(true)
    expect(convertToValue({ val: 'FALSE', type: 'BOOL' })).toBe(false)
    expect(convertToValue({ val: true, type: 'BOOL' })).toBe(true)
  })

  it('keeps quoted true as a string', () => {
    expect(convertToValue({ val: "'true'", type: 'BOOL' })).toBe('true')
    expect(convertToValue({ val: 'true', type: 'STRING' })).toBe('true')
  })

  it('keeps a BOOL loaded from a command string a boolean', () => {
    // As the history writes it: ITEM6 true
    const row = { type: 'BOOL' }
    row.val = paramValueFromText(row, 'true')
    expect(convertToValue(row)).toBe(true)
  })
})
