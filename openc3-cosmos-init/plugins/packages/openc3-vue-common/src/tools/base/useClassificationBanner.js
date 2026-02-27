/*
# Copyright 2026, OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { reactive, computed, onMounted } from 'vue'
import { OpenC3Api } from '@openc3/js-common/services'

/**
 * Composable to provide classification banner state and styles.
 *
 * Usage:
 * const { classification, classificationStyles, refresh } = useClassificationBanner()
 *
 * - `classification` is a reactive object:
 *   {
 *     text: '',
 *     fontColor: 'white',
 *     backgroundColor: 'red',
 *     topHeight: 0,
 *     bottomHeight: 0
 *   }
 *
 * - `classificationStyles` is a computed string you can bind to a root element's
 *   `style` attribute so CSS pseudo-elements can read the values via CSS variables.
 *
 * - `refresh()` will re-fetch the setting from the API.
 */
export function useClassificationBanner() {
  const classification = reactive({
    text: '',
    fontColor: 'white',
    backgroundColor: 'red',
    topHeight: 0,
    bottomHeight: 0,
  })

  const classificationStyles = computed(() => {
    // JavaScript can't access CSS pseudo-elements (::before and ::after).
    // Expose the values as CSS variables so stylesheets can pick them up.
    return [
      `--classification-text:"${classification.text}";`,
      `--classification-font-color:${classification.fontColor};`,
      `--classification-background-color:${classification.backgroundColor};`,
      `--classification-height-top:${classification.topHeight}px;`,
      `--classification-height-bottom:${classification.bottomHeight}px;`,
    ].join('')
  })

  async function refresh() {
    const api = new OpenC3Api()
    try {
      const response = await api.get_setting('classification_banner')
      if (response) {
        // Keep reactivity by assigning to properties rather than replacing the object.
        const parsed = JSON.parse(response)
        // Only assign known keys to avoid unexpected mutation
        if (typeof parsed === 'object' && parsed !== null) {
          if ('text' in parsed) classification.text = parsed.text
          if ('fontColor' in parsed) classification.fontColor = parsed.fontColor
          if ('backgroundColor' in parsed)
            classification.backgroundColor = parsed.backgroundColor
          if ('topHeight' in parsed) classification.topHeight = parsed.topHeight
          if ('bottomHeight' in parsed)
            classification.bottomHeight = parsed.bottomHeight
        }
      }
    } catch (e) {
      // intentionally swallow errors (matches original behavior)
    }
  }

  // Automatically load on mount (for usage inside components)
  onMounted(() => {
    refresh()
  })

  return {
    classification,
    classificationStyles,
    refresh,
  }
}

export default useClassificationBanner
