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

// Helpers for shared resources returned by OpenC3Api.get_shared_resources().
// A shared resource is only active in one scope at a time. Its members
// (interfaces, routers, microservices, targets) in other scopes are dormant.

// Build a map of member name to shared resource for the members of the given
// type in scope. Interface, router, and microservice members are named by their
// microservice name (SCOPE__INTERFACE__NAME). Pass shortNames to key interfaces
// and routers by their short name (NAME) instead.
export function sharedResourceMembers(
  resources,
  scope,
  type,
  shortNames = false,
) {
  const result = {}
  for (const resource of resources || []) {
    for (const member of resource.members?.[scope] || []) {
      if (member.type !== type) continue
      let name = member.name
      if (shortNames) name = name.split('__').slice(2).join('__')
      result[name] = resource
    }
  }
  return result
}

// Whether the shared resource's members in scope may be active
export function sharedResourceActive(resource, scope) {
  return resource?.state === 'ACTIVE' && resource?.owner === scope
}

// Short description of the shared resource state, e.g. 'Active in DEFAULT'
export function sharedResourceStatus(resource) {
  if (!resource) return ''
  if (resource.state === 'RELEASING') {
    if (resource.to) {
      return `Switching ${resource.owner} to ${resource.to}`
    }
    return `Releasing from ${resource.owner}`
  }
  if (resource.owner) return `Active in ${resource.owner}`
  return 'Not active in any scope'
}
