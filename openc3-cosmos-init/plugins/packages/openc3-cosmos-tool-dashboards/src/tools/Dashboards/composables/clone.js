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

import { toRaw } from 'vue'

// A deep copy of dashboard data (models, panels, settings): plain objects,
// arrays and primitives. Reactive proxies are unwrapped at every level
// first, since a model can hold proxies nested in plain objects (a panel
// spread from the panel dialog's reactive draft) and structuredClone
// refuses proxies.
function unwrap(value) {
  const raw = toRaw(value)
  if (Array.isArray(raw)) return raw.map(unwrap)
  if (raw && typeof raw === 'object' && !(raw instanceof Date)) {
    return Object.fromEntries(
      Object.entries(raw).map(([key, item]) => [key, unwrap(item)]),
    )
  }
  return raw
}

export function cloneData(value) {
  return structuredClone(unwrap(value))
}
