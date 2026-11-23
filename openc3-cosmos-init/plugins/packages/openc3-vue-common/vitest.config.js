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

import { defineConfig } from 'vitest/config'

// Unit tests for the pure modules (e.g. the command string parser), run in
// Node. Components need a browser and a running COSMOS: the Playwright tests
// cover them.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/__tests__/**/*.spec.js'],
  },
})
