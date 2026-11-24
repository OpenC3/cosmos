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

import {
  sharedResourceActive,
  sharedResourceMembers,
  sharedResourceStatus,
} from '@openc3/js-common/utils'

// Merge shared resource state into the Interfaces / Routers tab rows.
// Members of a shared resource that isn't active in this scope are marked
// dormant: their microservice isn't running so connect is replaced by
// Activate. Dormant members which never ran have no status so get a row added.
//
// @param rows [Array] Rows built from get_all_interface_info / get_all_router_info
// @param resources [Array] Result of get_shared_resources
// @param type [String] INTERFACE or ROUTER
export function applySharedResources(rows, resources, type) {
  const scope = window.openc3Scope
  const members = sharedResourceMembers(resources, scope, type, true)
  for (const [name, resource] of Object.entries(members)) {
    let row = rows.find((r) => r.name === name)
    if (!row) {
      row = {
        name: name,
        clients: 0,
        tx_q_size: 0,
        rx_q_size: 0,
        tx_bytes: 0,
        rx_bytes: 0,
        cmd_pkts: 0,
        tlm_pkts: 0,
      }
      rows.push(row)
    }
    row.sharedResource = resource.name
    if (!sharedResourceActive(resource, scope)) {
      row.dormant = true
      row.switching = resource.state === 'RELEASING'
      row.connected = `SHARED: ${sharedResourceStatus(resource)}`
      row.connectedClass = 'text-medium-emphasis'
      row.connect = 'Activate'
    }
  }
  return rows
}

// Confirm with the user then make the shared resource active in this scope
export async function activateSharedResource(vm, api, item) {
  const name = item.sharedResource
  const scope = window.openc3Scope
  try {
    await vm.$dialog.confirm(
      `Make shared resource ${name} active in scope ${scope}? Its microservices in the scope where it is active will be stopped first.`,
      { okText: 'Activate', cancelText: 'Cancel' },
    )
  } catch {
    return false // User cancelled
  }
  try {
    await api.switch_shared_resource(name)
    vm.$notify.normal({
      title: `Switching ${name} to ${scope}`,
      body: 'Its microservices will start once the other scope has stopped them',
    })
    return true
  } catch (error) {
    vm.$notify.serious({
      title: `Failed to switch ${name}`,
      body: error.message || String(error),
    })
    return false
  }
}
