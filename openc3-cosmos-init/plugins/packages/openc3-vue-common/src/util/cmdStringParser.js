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

// Parses command strings the way a user writes them in a script, e.g.
//   INST COLLECT with TYPE 'NORMAL', DURATION 1
//   cmd("INST COLLECT with TYPE 'NORMAL'", queue: "Q1", validate: false)
// Values are returned as written (quotes included), so the caller decides how
// to convert them against the command definition.

import { convertToValue, isArray, removeQuotes } from './cmdUtilities'

// Same tokens as OpenC3::Extract::SCANNING_REGULAR_EXPRESSION, which parses
// this text on the server: double or single quoted strings, arrays with one
// level of nesting, a comma, or a bare word
const TOKEN_REGEX =
  /"(?:[^\\"]|\\.)*"|'(?:[^\\']|\\.)*'|\[(?:[^\\[\]]|\\.|\[(?:[^\\[\]]|\\.)*\])*\]|,|[^\s,]+/g

// The scripting API methods that send a command from a single string
const METHOD_REGEX =
  /^cmd(?:_raw)?(?:_no_range_check|_no_hazardous_check|_no_checks)?$/

// "TARGET COMMAND" or "TARGET COMMAND with PARAM value, ..." into
// { target, command, params }. Throws with the same messages as the server.
export function parseCmdText(text) {
  const trimmed = (text || '').trim()
  if (trimmed === '') throw new Error('Command text must not be empty')

  const withMatch = /\s+with(?:\s+|$)/i.exec(trimmed)
  const head = withMatch ? trimmed.slice(0, withMatch.index) : trimmed
  const tail = withMatch
    ? trimmed.slice(withMatch.index + withMatch[0].length)
    : null
  if (tail !== null && tail.trim() === '') {
    throw new Error(`'with' must be followed by parameters: ${text}`)
  }
  const names = head.split(/\s+/)
  if (names.length < 2) {
    throw new Error(
      `Both Target Name and Command Name must be given: ${trimmed}`,
    )
  }
  if (names.length > 2) {
    throw new Error(
      `Only Target Name and Command Name must be given before 'with': ${trimmed}`,
    )
  }

  const params = {}
  if (tail !== null) {
    let keyword = null
    let value = null
    for (const token of tail.match(TOKEN_REGEX) || []) {
      if (token === ',') {
        if (keyword === null) {
          throw new Error(`Missing command parameter before comma: ${trimmed}`)
        }
        if (value === null) {
          throw new Error(`Missing value for ${keyword}: ${trimmed}`)
        }
        params[keyword] = value
        keyword = null
        value = null
      } else if (keyword === null) {
        keyword = token
      } else if (value === null) {
        value = token
      } else {
        throw new Error(`Missing comma in command parameters: ${trimmed}`)
      }
    }
    // A trailing comma leaves nothing pending, which the server allows
    if (keyword !== null) {
      if (value === null) {
        throw new Error(`Missing value for ${keyword}: ${trimmed}`)
      }
      params[keyword] = value
    }
  }
  return { target: names[0], command: names[1], params }
}

// parseCmdText, falling back to how CommandEditor parsed command text before
// it: a value runs to the next comma outside brackets, so unquoted values with
// spaces (e.g. "LABEL hello world" as Enterprise CommandQueue writes them)
// still parse. Returns null if neither can parse it.
export function parseCmdTextLenient(text) {
  try {
    return parseCmdText(text)
  } catch {
    // Not valid script syntax, try the lenient form
  }
  const parts = (text || '').trim().split(/\s+/)
  // The strict parse handles a bare TARGET COMMAND, so there's a 'with'
  if (parts.length < 3 || parts[2] !== 'with') return null
  const paramsString = text.split(' with ')[1] || ''
  const pairs = []
  let depth = 0
  let current = ''
  for (const char of paramsString) {
    if (char === '[') depth++
    if (char === ']') depth--
    if (char === ',' && depth === 0) {
      pairs.push(current.trim())
      current = ''
    } else {
      current += char
    }
  }
  if (current.trim() !== '') pairs.push(current.trim())
  const params = {}
  for (const pair of pairs) {
    const space = pair.indexOf(' ')
    if (space > 0) {
      params[pair.slice(0, space).trim()] = pair.slice(space + 1).trim()
    }
  }
  return { target: parts[0], command: parts[1], params }
}

// A command as pasted from a script or the Command Sender history: either
// bare command text or a cmd*("...") call. Returns
//   method: the cmd* method name, or null for bare text
//   target, command, params: see parseCmdText
//   queue: the queue: / queue= keyword (a name or false), undefined if absent
//   validate: the validate: / validate= keyword, undefined if absent
//   ignored: names of other keywords (e.g. timeout), which aren't applied
export function parseCmdLine(line) {
  let trimmed = (line || '').trim()
  const call = /^([A-Za-z_]\w*)\s*\(/.exec(trimmed)
  // Ruby also allows a call without parentheses: cmd "TARGET COMMAND ..."
  const bare = call ? null : /^([A-Za-z_]\w*)\s+(?=["'])/.exec(trimmed)
  const bareCall = bare && METHOD_REGEX.test(bare[1]) ? bare : null
  if (bareCall) {
    trimmed = stripComment(trimmed)
  } else if (call) {
    // A trailing comment after the call, as in a script line. Find the
    // parenthesis that closes the call, not the last one, which can be in
    // the comment, e.g. # collect (normal)
    const close = closingParen(trimmed, call[0].length)
    if (close !== -1 && /^\s*(?:;\s*)?#/.test(trimmed.slice(close + 1))) {
      trimmed = trimmed.slice(0, close + 1)
    }
  }
  trimmed = trimmed.replace(/;$/, '').trim()
  if (!call && !bareCall) {
    return {
      method: null,
      ...parseCmdText(trimmed),
      queue: undefined,
      validate: undefined,
      ignored: [],
    }
  }

  const method = (call || bareCall)[1]
  if (!METHOD_REGEX.test(method)) {
    throw new Error(`Unknown command method ${method}, expected cmd("...")`)
  }
  if (call && !trimmed.endsWith(')')) {
    throw new Error(`Missing the closing parenthesis: ${trimmed}`)
  }
  const args = call
    ? trimmed.slice(call[0].length, -1).trim()
    : trimmed.slice(bareCall[0].length).trim()
  const single = `Only the single string form is supported, e.g. ${method}("TARGET COMMAND with PARAM value")`
  const quote = args.charAt(0)
  if (quote !== '"' && quote !== "'") throw new Error(single)

  const { text, end } = readString(args, quote)
  const rest = args.slice(end).trim()
  if (rest !== '' && !rest.startsWith(',')) throw new Error(single)
  // Check the arguments before the text so a multiple argument call, e.g.
  // cmd("INST", "COLLECT", {...}), says so rather than what "INST" lacks
  const parts = rest === '' ? [] : splitTopLevel(rest.slice(1))
  const result = {
    method,
    target: '',
    command: '',
    params: {},
    queue: undefined,
    validate: undefined,
    ignored: [],
  }
  for (const part of parts) {
    const keyword = /^([A-Za-z_]\w*)\s*(?::|=)\s*(\S[\s\S]*)$/.exec(part)
    if (!keyword) {
      // A second positional argument, e.g. cmd("INST", "COLLECT", {...})
      if (/^["'{[]/.test(part)) throw new Error(single)
      throw new Error(`Invalid keyword argument: ${part}`)
    }
    const [, name, value] = keyword
    if (name === 'queue') {
      // nil / None is no queue, like leaving the keyword off
      if (/^(?:nil|None)$/.test(value)) continue
      result.queue = /^false$/i.test(value) ? false : unquote(value)
    } else if (name === 'validate') {
      if (!/^(?:true|false)$/i.test(value)) {
        throw new Error(`validate must be true or false: ${part}`)
      }
      result.validate = value.toLowerCase() === 'true'
    } else {
      result.ignored.push(name)
    }
  }
  return { ...result, ...parseCmdText(text) }
}

// The string literal starting at text[0], with backslash escapes of quotes
// and backslashes removed
function readString(text, quote) {
  let value = ''
  for (let i = 1; i < text.length; i++) {
    const char = text.charAt(i)
    if (char === '\\' && i + 1 < text.length) {
      const next = text.charAt(i + 1)
      value += next === quote || next === '\\' ? next : char + next
      i++
    } else if (char === quote) {
      return { text: value, end: i + 1 }
    } else {
      value += char
    }
  }
  throw new Error(`Unterminated string: ${text}`)
}

// The index of the parenthesis that closes a call whose arguments start at
// start, skipping quoted strings and nested brackets, or -1 if it isn't closed
function closingParen(text, start) {
  let quote = null
  let depth = 0
  for (let i = start; i < text.length; i++) {
    const char = text.charAt(i)
    if (quote) {
      if (char === '\\') {
        i++
      } else if (char === quote) {
        quote = null
      }
    } else if (char === '"' || char === "'") {
      quote = char
    } else if (char === '[' || char === '{' || char === '(') {
      depth++
    } else if (char === ']' || char === '}' || char === ')') {
      if (char === ')' && depth === 0) return i
      depth--
    }
  }
  return -1
}

// The text before a # comment outside quotes, for a call without
// parentheses (one with them finds its end with closingParen)
function stripComment(text) {
  let quote = null
  for (let i = 0; i < text.length; i++) {
    const char = text.charAt(i)
    if (quote) {
      if (char === '\\') {
        i++
      } else if (char === quote) {
        quote = null
      }
    } else if (char === '"' || char === "'") {
      quote = char
    } else if (char === '#') {
      return text.slice(0, i).trim()
    }
  }
  return text
}

// The comma separated keyword arguments after the command string, keeping
// commas inside quotes and brackets
function splitTopLevel(text) {
  const parts = []
  let current = ''
  let quote = null
  let depth = 0
  for (let i = 0; i < text.length; i++) {
    const char = text.charAt(i)
    if (quote) {
      if (char === '\\') {
        current += char + text.charAt(i + 1)
        i++
        continue
      }
      if (char === quote) quote = null
    } else if (char === '"' || char === "'") {
      quote = char
    } else if (char === '[' || char === '{' || char === '(') {
      depth++
    } else if (char === ']' || char === '}' || char === ')') {
      depth--
    } else if (char === ',' && depth === 0) {
      parts.push(current.trim())
      current = ''
      continue
    }
    current += char
  }
  parts.push(current.trim())
  return parts
}

function unquote(value) {
  const first = value.charAt(0)
  if ((first === '"' || first === "'") && value.endsWith(first)) {
    return value.slice(1, -1)
  }
  return value
}

// A parameter value as written in a command string (see parseCmdText) to the
// form a CommandEditor row holds: a state's value for a state name or raw
// value, a quoted string for STRING and BLOCK, otherwise as written. row is
// { states, type } with type the data type (an array's element type).
export function paramValueFromText(row, value) {
  const unquoted = removeQuotes(value)
  if (row.states) {
    const stateName = Object.keys(row.states).find(
      (state) => state.toUpperCase() === unquoted.toUpperCase(),
    )
    if (stateName !== undefined) {
      return row.states[stateName].value
    }
    // A state's raw value, e.g. TYPE 1, selects that state
    const raw = convertToValue({ val: unquoted, type: row.type })
    const state = Object.values(row.states).find((s) => s.value === raw)
    if (state) return state.value
    // Not a state, e.g. a manually entered value
    return value
  }
  if (row.type === 'STRING' || row.type === 'BLOCK') {
    // Quoted, hex for binary data, or an array of strings, as written.
    // Otherwise quote it so it's sent as a string even if it looks like a
    // number.
    if (unquoted !== value || /^0x/i.test(value) || isArray(value)) {
      return value
    }
    return `'${value}'`
  }
  return value
}
