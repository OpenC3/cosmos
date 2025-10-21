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
  <!-- This dialog does not have a cancel button and has no user input, so it does not need to be persistent -->
  <v-dialog v-model="show" :width="width" scrollable>
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span> {{ title }} </span>
        <v-spacer />
        <div class="mx-2">
          <v-btn
            icon="mdi-download"
            variant="text"
            density="compact"
            data-test="downloadIcon"
            aria-label="Download Content"
            @click="download"
          />
        </div>
      </v-toolbar>
      <v-card-text style="max-height: 80vh">
        <div class="pa-3">
          <span class="text">{{ text }}</span>
        </div>
      </v-card-text>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn variant="flat" @click="show = !show"> Ok </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
export default {
  props: {
    modelValue: Boolean, // modelValue is the default prop when using v-model
    text: String,
    title: String,
    width: {
      type: Number,
      default: 800,
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
  methods: {
    download: function () {
      const blob = new Blob([this.text], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', `${this.title}.txt`)
      link.click()
    },
  },
}
</script>

<style scoped>
.text {
  white-space: pre-wrap;
}
</style>
