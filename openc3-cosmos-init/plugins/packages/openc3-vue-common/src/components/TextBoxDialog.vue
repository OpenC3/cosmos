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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" width="600">
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
            @click="download"
          />
        </div>
      </v-toolbar>
      <div class="pa-2">
        <v-card-text>
          <v-textarea
            v-model="dialogText"
            readonly
            rows="15"
            data-test="dialogText"
          />
        </v-card-text>
      </div>
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
    modelValue: Boolean,
    text: String,
    title: String,
  },
  computed: {
    dialogText: function () {
      return this.text
    },
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
      const blob = new Blob([this.dialogText], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', `${this.title}__error.txt`)
      link.click()
    },
  },
}
</script>
