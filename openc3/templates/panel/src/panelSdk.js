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

// The Dashboards panel SDK: composables, option readers, formatting and
// building blocks shared with the built-in panels. Dashboards passes it to
// each panel's entry file when it loads the panel, so it's filled in before
// any panel component is set up. Shared by every panel in this plugin.
//
// https://docs.openc3.com/docs/guides/custom-panels
export const sdk = {}

export function setSdk(value) {
  Object.assign(sdk, value)
}
