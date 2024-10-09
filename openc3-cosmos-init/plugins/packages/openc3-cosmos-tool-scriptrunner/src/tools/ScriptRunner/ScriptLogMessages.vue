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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-card>
      <v-card-title>
        <v-tooltip location="top">
          <template v-slot:activator="{ props }">
            <div v-bind="props">
              <v-btn
                icon
                class="mx-2"
                data-test="download-log"
                @click="downloadLog"
              >
                <v-icon> mdi-download </v-icon>
              </v-btn>
            </div>
          </template>
          <span> Download Log </span>
        </v-tooltip>
        Script Messages
        <v-spacer />
        <v-select
          density="compact"
          hide-details
          variant="outlined"
          :items="messageOrderOptions"
          v-model="messageOrder"
          class="mr-2"
          style="max-width: 170px"
          data-test="message-order"
        />
        <v-spacer />
        <v-text-field
          v-model="search"
          label="Search"
          prepend-inner-icon="mdi-magnify"
          clearable
          variant="outlined"
          density="compact"
          single-line
          hide-details
          class="search"
          data-test="search-messages"
        />

        <v-tooltip location="top">
          <template v-slot:activator="{ props }">
            <div v-bind="props">
              <v-btn icon class="mx-2" data-test="clear-log" @click="clearLog">
                <v-icon> mdi-delete </v-icon>
              </v-btn>
            </div>
          </template>
          <span> Clear Log </span>
        </v-tooltip>
      </v-card-title>
      <v-data-table
        id="script-log-messages"
        style="overflow: auto"
        :headers="headers"
        :items="messages"
        :search="search"
        :items-per-page="-1"
        hide-default-footer
        density="compact"
        data-test="output-messages"
      />
    </v-card>
  </div>
</template>

<script>
import { format } from 'date-fns'

export default {
  props: {
    value: {
      type: Array,
      required: true,
    },
  },
  data() {
    return {
      search: '',
      headers: [{ title: 'Message', value: 'message', sortable: false }],
      messageOrderOptions: ['Newest on Top', 'Newest on Bottom'],
      messageOrder: 'Newest on Top',
    }
  },
  watch: {
    messageOrder: function (newValue, oldValue) {
      this.$emit('sort', newValue)
    },
  },
  computed: {
    messages: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
  },
  methods: {
    downloadLog() {
      const output = this.messages.map((message) => message.message).join('\n')
      const blob = new Blob([output], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute(
        'download',
        format(Date.now(), 'yyyy_MM_dd_HH_mm_ss') + '_sr_message_log.txt',
      )
      link.click()
    },
    clearLog: function () {
      this.$dialog
        .confirm('Are you sure you want to clear the log?', {
          okText: 'Clear',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          this.messages = []
        })
        .catch(function (err) {
          // Canceling the dialog forces catch and sets err to true
        })
    },
  },
}
</script>
