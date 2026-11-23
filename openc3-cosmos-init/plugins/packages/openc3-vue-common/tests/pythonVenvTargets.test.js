/* Copyright 2026 OpenC3, Inc. All Rights Reserved. See LICENSE.md. */

import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  SHARED_VENV,
  wheelInstallTargets,
} from '../src/tools/admin/tabs/pythonVenvTargets.js'

// The /openc3-api/packages python response: 'cached' is the UV cache and
// 'shared' the PYTHONUSERBASE folder; every other key is a plugin venv.

test('offers no choice when the only keys are the cache and shared folder', () => {
  // A seeded cache used to open the venv dialog with nothing to pick
  assert.deepEqual(
    wheelInstallTargets({ cached: ['numpy-2.4.6'], shared: ['requests-2.34.2'] }),
    [],
  )
  assert.deepEqual(wheelInstallTargets({ cached: ['numpy-2.4.6'] }), [])
  assert.deepEqual(wheelInstallTargets({}), [])
})

test('offers each plugin venv, sorted, then the shared folder', () => {
  assert.deepEqual(
    wheelInstallTargets({
      cached: ['numpy-2.4.6'],
      DEFAULT__zeta__0: [],
      DEFAULT__alpha__0: ['requests-2.34.2'],
    }),
    ['DEFAULT__alpha__0', 'DEFAULT__zeta__0', SHARED_VENV],
  )
})

test('offers the shared folder even when it has no packages yet', () => {
  // names() drops the 'shared' key while the folder is empty
  assert.deepEqual(wheelInstallTargets({ DEFAULT__demo__0: [] }), [
    'DEFAULT__demo__0',
    SHARED_VENV,
  ])
})
