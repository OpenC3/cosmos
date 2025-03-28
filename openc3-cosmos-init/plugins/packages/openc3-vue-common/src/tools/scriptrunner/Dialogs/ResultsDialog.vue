<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" scrollable width="800">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span> Script Results </span>
        <v-spacer />
      </v-toolbar>
      <div class="pa-2">
        <v-card-text style="width: 100%; max-height: 80vh; overflow: auto">
          <v-textarea
            readonly
            hide-details
            density="compact"
            auto-grow
            :model-value="text"
          />
        </v-card-text>
      </div>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn variant="outlined" @click="downloadResults"> Download </v-btn>
        <v-btn variant="flat" @click="show = !show" ref="okButton"> Ok </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { format } from 'date-fns'

export default {
  components: {},
  props: {
    modelValue: {
      type: Boolean,
      required: true,
    },
    text: {
      type: String,
      required: true,
    },
  },
  computed: {
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
  },
  mounted() {
    // Focus the OK button so it's easy to hit Enter to close
    setTimeout(() => {
      this.$refs.okButton.$el.focus()
    })
  },
  methods: {
    downloadResults() {
      const blob = new Blob([this.text], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute(
        'download',
        format(Date.now(), 'yyyy_MM_dd_HH_mm_ss') + '_suite_results.txt',
      )
      link.click()
    },
  },
}
</script>
