/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import TimeFilters from '@/util/timeFilters'

// Composition API access to the TimeFilters mixin methods.
// Call methods on the returned object (don't destructure) since
// they reference each other through `this`.
export function useTimeFilters() {
  return TimeFilters.methods
}
