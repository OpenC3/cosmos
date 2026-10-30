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

// Shared by the Script Runner file explorer and quick open palette

import { Api } from '@openc3/js-common/services'

// Matches target_file.rb TEMP_FOLDER
export const TEMP_FOLDER = '__TEMP__'

// Binary files can't be shown in the editor so they aren't openable
const BINARY_EXTENSIONS = new Set([
  'png',
  'jpg',
  'jpeg',
  'gif',
  'bmp',
  'ico',
  'webp',
  'tif',
  'tiff',
  'mp4',
  'mov',
  'avi',
  'mkv',
  'webm',
  'mp3',
  'wav',
  'pdf',
  'zip',
  'gz',
  'tar',
  'bin',
])

export function extension(path) {
  const name = path.split('/').pop()
  return name.includes('.') ? name.split('.').pop().toLowerCase() : ''
}

export function isBinary(path) {
  return BINARY_EXTENSIONS.has(extension(path))
}

// Only procedures (and unsaved __TEMP__ scripts) are navigable
export function isProcedure(path) {
  const [target, folder] = path.split('/')
  return target === TEMP_FOLDER || folder === 'procedures'
}

// Targets to list scripts for, with __TEMP__ last
export async function loadTargets() {
  const response = await Api.get('/openc3-api/targets')
  return [...response.data, TEMP_FOLDER]
}

// Procedures in a target as { path, modified }. The API marks files
// modified on the server with a trailing '*'.
export async function loadProcedures(target) {
  const response = await Api.get('/script-api/scripts', {
    params: { target },
  })
  return response.data
    .map((file) => {
      const modified = file.endsWith('*')
      return { path: modified ? file.slice(0, -1) : file, modified }
    })
    .filter((file) => isProcedure(file.path))
}

// Human friendly name for a script, e.g. my_test_suite.rb -> My Test Suite
export function displayName(path) {
  const name = path
    .split('/')
    .pop()
    .replace(/\.[^.]+$/, '')
  return name
    .split(/[_\-\s]+/)
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')
}

const LANGUAGES = { rb: 'Ruby', py: 'Python' }

// Temp scripts are unsaved scratch files with generated names, not
// something users look up by name
export function isListed(path) {
  return (
    isProcedure(path) && !isBinary(path) && !path.startsWith(`${TEMP_FOLDER}/`)
  )
}

// Describe a procedure by name and target rather than by file path
export function toProcedure(path) {
  const [target, ...rest] = path.split('/')
  // Drop the 'procedures' folder and filename, keep any subfolders
  const folders = rest.slice(1, -1)
  return {
    path,
    target,
    name: displayName(path),
    folders: folders.join(' · '),
    location: [target, ...folders].join(' · '),
    language: LANGUAGES[extension(path)] || extension(path).toUpperCase(),
  }
}

// Lower scores rank higher, null means no match
function scoreToken(item, token) {
  const name = item.name.toLowerCase()
  if (name.startsWith(token)) return 0
  if (name.split(' ').some((word) => word.startsWith(token))) return 1
  if (name.includes(token)) return 2
  if (item.location.toLowerCase().includes(token)) return 3
  if (item.path.toLowerCase().includes(token)) return 4
  // Characters in order, e.g. 'mts' matches 'My Test Suite'
  let index = 0
  for (const char of name.replace(/ /g, '')) {
    if (char === token[index]) index++
  }
  return index === token.length ? 5 : null
}

// Procedures matching every word of the query, best match first
export function searchProcedures(items, query, limit = Infinity) {
  const tokens = query.toLowerCase().split(/\s+/).filter(Boolean)
  const scored = []
  for (const item of items) {
    let total = 0
    for (const token of tokens) {
      const score = scoreToken(item, token)
      if (score === null) {
        total = null
        break
      }
      total += score
    }
    if (total !== null) scored.push({ item, total })
  }
  return scored
    .sort((a, b) => a.total - b.total || a.item.name.localeCompare(b.item.name))
    .slice(0, limit)
    .map(({ item }) => item)
}
