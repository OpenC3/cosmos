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

// Keys of the /openc3-api/packages python response that are not plugin venvs:
// the UV download cache and the shared PYTHONUSERBASE folder
export const CACHED_VENV = 'cached'
export const SHARED_VENV = 'shared'
const NON_VENV_KEYS = new Set([CACHED_VENV, SHARED_VENV])

// Plugin venv names in the python response, sorted
export function pluginVenvNames(python) {
  return Object.keys(python ?? {})
    .filter((key) => !NON_VENV_KEYS.has(key))
    .sort((a, b) => a.localeCompare(b))
}

// Where an uploaded wheel can be installed. Empty when there are no plugin
// venvs, in which case the wheel goes to the shared folder without asking.
// Otherwise every plugin venv, then the shared folder, which is always a valid
// target even before it holds any packages.
export function wheelInstallTargets(python) {
  const venvs = pluginVenvNames(python)
  return venvs.length > 0 ? [...venvs, SHARED_VENV] : []
}
