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

// The targets of a MICROSERVICE_GROUP run their microservices in
// SCOPE__MULTIGROUP__<GROUP> (Ruby) and SCOPE__PYMULTIGROUP__<GROUP> (Python)
const GROUP_TYPE = /^(PY)?MULTIGROUP$/

/** Returns 'SCOPE__GROUP' for a microservice group microservice, else null */
export function microserviceGroupKey(name) {
  const [scope, type, ...rest] = name.split('__')
  if (!scope || !type || !rest.length || !GROUP_TYPE.test(type)) return null
  return `${scope}__${rest.join('__')}`
}

/**
 * Arranges microservices for display. A microservice whose parent (such as a
 * MULTI or MULTIGROUP process that runs it as a thread) is in the list is shown
 * under that parent. A microservice group's MULTIGROUP and PYMULTIGROUP are
 * shown under a header for the group. Collapsed keys (a parent's name or a group header's
 * key) hide what is under them.
 *
 * @param {Array<{name: string, parent?: string}>} microservices sorted by name
 * @param {Set<string>} collapsed keys of collapsed parents and groups
 * @returns {Array} rows of either
 *   { type: 'group', key, scope, name, count, collapsed } or
 *   { type: 'microservice', key, microservice, depth, childCount, collapsed }
 */
export function microserviceRows(microservices, collapsed = new Set()) {
  const byName = Object.fromEntries(microservices.map((ms) => [ms.name, ms]))
  const hasParent = (ms) =>
    !!ms?.parent && ms.parent !== ms.name && !!byName[ms.parent]
  const children = {}
  const topLevel = []
  for (const ms of microservices) {
    // Parents only run their children, so nest one level. A parent that has a
    // parent of its own (which COSMOS doesn't create) stays at the top level,
    // which also keeps a parent cycle from hiding both microservices.
    if (hasParent(ms) && !hasParent(byName[ms.parent])) {
      ;(children[ms.parent] ||= []).push(ms)
    } else {
      topLevel.push(ms)
    }
  }

  // Gather each group's top level microservices into one entry placed where
  // its first microservice would be
  const entries = []
  const groups = {}
  for (const ms of topLevel) {
    const groupKey = microserviceGroupKey(ms.name)
    if (groupKey) {
      if (!groups[groupKey]) {
        groups[groupKey] = []
        entries.push({ groupKey })
      }
      groups[groupKey].push(ms)
    } else {
      entries.push({ microservice: ms })
    }
  }

  const rows = []
  const addMicroservice = (ms, depth) => {
    const kids = children[ms.name] || []
    const isCollapsed = kids.length > 0 && collapsed.has(ms.name)
    rows.push({
      type: 'microservice',
      key: ms.name,
      microservice: ms,
      depth,
      childCount: kids.length,
      collapsed: isCollapsed,
    })
    if (isCollapsed) return
    for (const kid of kids) addMicroservice(kid, depth + 1)
  }
  const countAll = (ms) =>
    1 + (children[ms.name] || []).reduce((sum, kid) => sum + countAll(kid), 0)

  for (const entry of entries) {
    if (entry.microservice) {
      addMicroservice(entry.microservice, 0)
      continue
    }
    const members = groups[entry.groupKey]
    const [scope, ...rest] = entry.groupKey.split('__')
    const isCollapsed = collapsed.has(entry.groupKey)
    rows.push({
      type: 'group',
      key: entry.groupKey,
      scope,
      name: rest.join('__'),
      count: members.reduce((sum, ms) => sum + countAll(ms), 0),
      collapsed: isCollapsed,
    })
    if (isCollapsed) continue
    for (const ms of members) addMicroservice(ms, 1)
  }
  return rows
}
