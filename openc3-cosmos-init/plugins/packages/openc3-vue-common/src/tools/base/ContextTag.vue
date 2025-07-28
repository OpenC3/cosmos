<!--
# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div
    v-if="contextTag.text"
    class="context-tag mr-2 mt-4"
    :style="{ 
      color: contextTag.fontColor,
      backgroundColor: contextTag.backgroundColor
    }"
  >
    {{ contextTag.text }}
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'

export default {
  name: 'ContextTag',
  data() {
    return {
      api: new OpenC3Api(),
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
    getContextTagSettings() {
      return this.api
      .get_setting('context_tag')
      .then((response) => {
        if (response) {
          const parsed = JSON.parse(response)
          this.contextTag = {
            text: parsed.text,
            fontColor: parsed.fontColor,
            backgroundColor: parsed.backgroundColor,
          }
        }
      })
      .catch((error) => {
        console.error(error)
      })
    },
    startContextTagAutoRefresh() {
      this.stopContextTagAutoRefresh()
      this.contextTagRefreshInterval = setInterval(() => {
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
  padding: .1875rem .5rem;
  display: flex;
  align-items: center;
  justify-content: center;
}
</style>