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

// The command definition and the parameters a user can set, with hidden,
// reserved and target-ignored parameters left out. Shared by the COMMAND
// panel and its editor so both always offer the same parameters.
export async function loadCommandParams(api, targetName, commandName) {
  const [target, command] = await Promise.all([
    api.get_target(targetName),
    api.get_cmd(targetName, commandName),
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
  return { command, params }
}
