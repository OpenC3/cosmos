<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div
    v-if="contextTag.text"
    class="context-tag mr-2 mt-4"
    :style="{
      color: contextTag.fontColor,
      backgroundColor: contextTag.backgroundColor,
    }"
  >
    {{ contextTag.text }}
  </div>
</template>

<script>
import { getCachedSetting, invalidateCachedSetting } from '@/util'

export default {
  name: 'ContextTag',
  data() {
    return {
      contextTag: {
        text: null,
        fontColor: null,
        backgroundColor: null,
      },
      contextTagRefreshInterval: null,
    }
  },
  created() {
    this.getContextTagSettings().then(() => {
      if (this.contextTag.text) {
        this.startContextTagAutoRefresh()
      }
    })
  },
  beforeUnmount() {
    this.stopContextTagAutoRefresh()
  },
  methods: {
    // The first read joins the batched get_settings the rest of the base
    // components issue on page load. getCachedSetting never rejects - it falls
    // back on failure - so there's nothing here to catch.
    getContextTagSettings() {
      return getCachedSetting('context_tag').then((response) => {
        if (!response) return
        try {
          const parsed = JSON.parse(response)
          this.contextTag = {
            text: parsed.text,
            fontColor: parsed.fontColor,
            backgroundColor: parsed.backgroundColor,
          }
        } catch (error) {
          // Malformed setting, keep whatever we're already showing. Still a real
          // problem worth reporting, unlike the auth errors this used to log.
          console.error(error)
        }
      })
    },
    startContextTagAutoRefresh() {
      this.stopContextTagAutoRefresh()
      this.contextTagRefreshInterval = setInterval(() => {
        // The cache is write-once per session, so drop our entry first or every
        // refresh after the first would be served the same stale value
        invalidateCachedSetting('context_tag')
        this.getContextTagSettings()
      }, 60000)
    },
    stopContextTagAutoRefresh() {
      if (this.contextTagRefreshInterval) {
        clearInterval(this.contextTagRefreshInterval)
        this.contextTagRefreshInterval = null
      }
    },
  },
}
</script>

<style scoped>
/* Custom CSS as the button color override is not possible. Styling to be close to Astro App States */
.context-tag {
  border-radius: 4px;
  height: 38px;
  font-family: var(--font-body-2-font-family);
  padding: 0.1875rem 0.5rem;
  display: flex;
  align-items: center;
  justify-content: center;
}
</style>
