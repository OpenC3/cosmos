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

import { onMounted, onUnmounted, reactive } from 'vue'

// Where the visible page is between the COSMOS app bar (with any
// classification banner above it) and the footer, in pixels from the top
// and bottom of the window: { top, bottom }. Measured, since the tool base
// styles the app bar taller than Vuetify's --v-layout-top says. Updated as
// the window or the bars change size.
export function useChromeInsets() {
  const insets = reactive({ top: 0, bottom: 0 })
  const bar = () =>
    document.getElementById('openc3-app-toolbar') ||
    document.querySelector('.v-app-bar')
  const footer = () => document.getElementById('footer')

  function measure() {
    const top = bar()?.getBoundingClientRect().bottom ?? 0
    const footerTop = footer()?.getBoundingClientRect().top
    insets.top = Math.max(0, Math.round(top))
    insets.bottom =
      footerTop === undefined
        ? 0
        : Math.max(0, Math.round(window.innerHeight - footerTop))
  }

  // The bars are on the page before the tool mounts, so this is right from
  // the first render
  measure()
  let observer = null
  onMounted(() => {
    window.addEventListener('resize', measure)
    observer = new ResizeObserver(measure)
    for (const el of [bar(), footer()]) if (el) observer.observe(el)
  })
  onUnmounted(() => {
    window.removeEventListener('resize', measure)
    observer?.disconnect()
  })
  return insets
}
