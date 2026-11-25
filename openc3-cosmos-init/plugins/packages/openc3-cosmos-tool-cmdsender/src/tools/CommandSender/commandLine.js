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

// Commands written the way the user would script them, e.g.
//   cmd("INST COLLECT with TYPE 'NORMAL', DURATION 1", queue: "Q1")
// for the history (from what the server sent) and the command line (from the
// form, before it's sent). parseCmdLine in vue-common reads them back.

import { convertToString, convertToValue } from '@openc3/vue-common/util'

// A keyword argument in the scripting language: Ruby or Python
export function formatKeyword(name, value, python = false) {
  if (value === false) {
    return python ? `${name}=False` : `${name}: false`
  }
  return python ? `${name}=${value}` : `${name}: ${value}`
}

// A parameter value as written in the command string. Strings are quoted,
// with double quotes if they contain a single quote, so they parse back.
function formatValue(value, obfuscated) {
  if (obfuscated) return "'*****'"
  const text = convertToString(value)
  if (
    typeof value === 'string' &&
    text.charAt(0) !== "'" &&
    text.charAt(0) !== '"'
  ) {
    const quote = text.includes("'") && !text.includes('"') ? '"' : "'"
    return `${quote}${text}${quote}`
  }
  return text
}

// method is the cmd* scripting method, e.g. cmd_no_range_check. command is
// { target_name, cmd_name, cmd_params, obfuscated_items } as the cmd API
// returns it. queueName: a queue's name, false (no queue), or null to leave
// the keyword off. python writes the keywords in Python, otherwise Ruby.
export function formatCmd(method, command, options = {}) {
  const obfuscated = command.obfuscated_items || []
  const params = Object.entries(command.cmd_params || {}).map(
    ([name, value]) =>
      `${name} ${formatValue(value, obfuscated.includes(name))}`,
  )
  return writeCmd(
    method,
    `${command.target_name} ${command.cmd_name}`,
    params,
    options,
  )
}

// The command the form's rows would send, written as formatCmd writes it.
// Rows are CommandEditor's: parameters without a value (null, e.g. a
// required parameter not set yet) aren't sent so they're left off, and
// obfuscated values are masked as the history masks them. raw: parameter
// conversions are disabled, so states are written as their values.
export function formatFormCmd(
  method,
  targetName,
  commandName,
  rows,
  { raw = false, ...options } = {},
) {
  const params = []
  for (const row of rows) {
    if (row.val === null || row.val === undefined) continue
    let value
    try {
      value = row.obfuscate
        ? formatValue(null, true)
        : formatValue(convertToValue(row, { raw }), false)
    } catch {
      // A value that can't be converted, e.g. a malformed array: as typed,
      // Send reports it
      value = String(row.val)
    }
    params.push(`${row.parameter_name} ${value}`)
  }
  return writeCmd(method, `${targetName} ${commandName}`, params, options)
}

// method("TARGET COMMAND with PARAM value, ...", keywords...)
function writeCmd(
  method,
  name,
  params,
  { queueName = null, disableCommandValidation = false, python = false } = {},
) {
  let text = name
  if (params.length > 0) {
    text += ` with ${params.join(', ')}`
  }
  // Escaped like a script string literal, so values with double quotes
  // (e.g. string arrays) copy into a script and load back from history
  const escaped = text
    .replaceAll('\\', String.raw`\\`)
    .replaceAll('"', String.raw`\"`)
  const keywords = []
  if (queueName !== null) {
    const queue = queueName === false ? false : `"${queueName}"`
    keywords.push(formatKeyword('queue', queue, python))
  }
  if (disableCommandValidation) {
    keywords.push(formatKeyword('validate', false, python))
  }
  const rest = keywords.length > 0 ? `, ${keywords.join(', ')}` : ''
  return `${method}("${escaped}"${rest})`
}
