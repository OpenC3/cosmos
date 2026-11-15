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
import { compactNumber } from '../composables/format'

describe('compactNumber', () => {
  it('passes NaN and infinities through as text', () => {
    expect(compactNumber(Number.NaN)).toBe('NaN')
    expect(compactNumber(Number.POSITIVE_INFINITY)).toBe('Infinity')
    expect(compactNumber(Number.NEGATIVE_INFINITY)).toBe('-Infinity')
  })

  it.each([
    [-0.0000047, '0.00'],
    [0.4868, '0.49'],
    [999.994, '999.99'],
    [999.999, '1.00k'],
    [1000, '1.00k'],
    [12345, '12.35k'],
    [999994, '999.99k'],
    [999999, '1.00M'],
    [1234567, '1.23M'],
    [-10113449.99, '-10.11M'],
    [2.5e9, '2.50B'],
    [42, '42'],
    [-7, '-7'],
  ])('%s -> %s', (value, text) => {
    expect(compactNumber(value)).toBe(text)
  })
})
