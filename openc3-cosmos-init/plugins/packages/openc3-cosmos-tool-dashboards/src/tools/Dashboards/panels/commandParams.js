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

// Same list as CommandEditor in vue-common: items every packet has that
// aren't real command parameters
const RESERVED = [
  'PACKET_TIMESECONDS',
  'PACKET_TIMEFORMATTED',
  'RECEIVED_TIMESECONDS',
  'RECEIVED_TIMEFORMATTED',
  'RECEIVED_COUNT',
]

// get_target / get_cmd promises, keyed by 'TARGET' and 'TARGET COMMAND', so
// every COMMAND panel and the panel dialog share one request per definition
const targets = new Map()
const commands = new Map()

// The cached promise for `key`, or a new one from `fetch`. A failed request
// is dropped so the next call retries.
function cached(cache, key, fetch) {
  if (!cache.has(key)) {
    cache.set(
      key,
      fetch().catch((error) => {
        cache.delete(key)
        throw error
      }),
    )
  }
  return cache.get(key)
}

// Forget the cached definitions, e.g. after plugins change
export function clearCommandCache() {
  targets.clear()
  commands.clear()
}

// The command definition and the parameters a user can set, with hidden,
// reserved and target-ignored parameters left out. Shared by the COMMAND
// panel and its editor so both always offer the same parameters.
export async function loadCommandParams(api, targetName, commandName) {
  const [target, command] = await Promise.all([
    cached(targets, targetName, () => api.get_target(targetName)),
    cached(commands, `${targetName} ${commandName}`, () =>
      api.get_cmd(targetName, commandName),
    ),
  ])
  const ignored = target?.ignored_parameters || []
  const params = command.items
    .filter(
      (p) =>
        !p.hidden && !RESERVED.includes(p.name) && !ignored.includes(p.name),
    )
    .map((p) => ({
      name: p.name,
      states: p.states || null,
      units: p.units || '',
      type: p.data_type,
      required: p.required,
      default: p.default,
      description: p.description,
    }))
  // A copy, as the definition is shared and CommandPanel marks its own
  // command hazardous when the server says so
  return { command: { ...command }, params }
}

// Names of the required parameters with no value in `values`. Only
// `names` are checked when given (e.g. the hidden ones).
export function unsetRequired(params, values, names = null) {
  return params
    .filter(
      (param) =>
        param.required &&
        (!names || names.includes(param.name)) &&
        [undefined, null, ''].includes(values[param.name]),
    )
    .map((param) => param.name)
}
