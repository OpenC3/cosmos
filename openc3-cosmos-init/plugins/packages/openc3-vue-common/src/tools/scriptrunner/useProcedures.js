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

// Procedure list for the Script Runner library, shared so every
// instance loads once and stays in sync

import { ref } from 'vue'
import {
  isListed,
  loadProcedures,
  loadTargets,
  toProcedure,
} from '@/tools/scriptrunner/scriptFiles'

const procedures = ref([])
const loading = ref(false)
let pending = null

// Several navigators can ask at once so share the in-flight request
function load() {
  pending ??= (async () => {
    loading.value = true
    try {
      const targets = await loadTargets()
      const files = await Promise.all(targets.map(loadProcedures))
      procedures.value = files
        .flat()
        .filter((file) => isListed(file.path))
        .map((file) => toProcedure(file.path))
    } finally {
      loading.value = false
      pending = null
    }
  })()
  return pending
}

// Procedures grouped by target, each sorted by name. Sections with
// grouped: true are a single target's procedures.
function sections() {
  const result = []
  const byTarget = new Map()
  for (const item of procedures.value) {
    if (!byTarget.has(item.target)) byTarget.set(item.target, [])
    byTarget.get(item.target).push(item)
  }
  for (const [target, items] of byTarget) {
    items.sort((a, b) => a.name.localeCompare(b.name))
    result.push({ title: target, items, grouped: true })
  }
  return result
}

export function useProcedures() {
  return {
    procedures,
    loading,
    load,
    sections,
  }
}
