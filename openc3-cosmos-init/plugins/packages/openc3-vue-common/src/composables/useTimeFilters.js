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

import {
  formatDate,
  formatDateTime,
  formatDateTimeHMS,
  formatNanoseconds,
  formatSeconds,
  formatTime,
  formatTimeHMS,
  formatTimestamp,
  formatUtcToLocal,
  parseDateTime,
} from '@/util/timeFilters'

// Composition API access to the time formatting functions (the same ones the
// TimeFilters mixin uses). They're plain functions, so destructuring is fine.
export function useTimeFilters() {
  return {
    parseDateTime,
    formatUtcToLocal,
    formatDateTime,
    formatDateTimeHMS,
    formatDate,
    formatTime,
    formatTimeHMS,
    formatTimestamp,
    formatSeconds,
    formatNanoseconds,
  }
}
