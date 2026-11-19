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

// Tells the shared OpenC3 tracking script about client-side page changes.
// The first page load is already tracked by the script itself.
export function onRouteDidUpdate({ location, previousLocation }) {
  if (!previousLocation) return;

  const currentPath = location.pathname + location.search;
  const previousPath = previousLocation.pathname + previousLocation.search;

  // Ignore repeat notifications and hash-only (in-page anchor) changes.
  if (currentPath === previousPath) return;

  if (typeof window !== "undefined") {
    window.oc3?.trackPage?.();
  }
}
