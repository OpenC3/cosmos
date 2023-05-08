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
  <v-dialog v-model="show" width="800">
    <v-card>
      <v-system-bar>
        <v-spacer />
        <span>Input Metadata</span>
        <v-spacer />
      </v-system-bar>
      <div class="pa-2">
        <v-card-text>
          <v-data-table
            :headers="eventHeaders"
            :items="metadata"
            :search="search"
            sort-by="start"
          >
            <template v-slot:no-data>
              <span> No events </span>
            </template>
            <template v-slot:item.start="{ item }">
              {{ logFormat(item.start) }}
            </template>
            <template v-slot:item.metadata="{ item }">
              {{ metadataFormat(item) }}
            </template>
            <template v-slot:item.actions="{ item }">
              <v-icon small class="mr-2" @click="editAction(item)">
                mdi-pencil
              </v-icon>
              <v-icon small @click="deleteAction(item)"> mdi-delete </v-icon>
            </template>
          </v-data-table>
        </v-card-text>
      </div>
      <v-card-actions>
        <v-spacer />
        <v-btn
          @click="cancel"
          class="mx-2"
          outlined
          data-test="metadata-dialog-cancel"
        >
          Cancel
        </v-btn>
        <v-btn
          @click="updateMetadata"
          class="mx-2"
          color="primary"
          data-test="metadata-dialog-save"
          :disabled="!!inputError"
        >
          Ok
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { format } from 'date-fns'
import Api from '@openc3/tool-common/src/services/api'

export default {
  components: {},
  props: {
    value: {
      type: Boolean,
      required: true,
    },
  },
  data() {
    return {
      lastUpdated: null,
      search: '',
      metadata: [],
      eventHeaders: [
        { text: 'Start', value: 'start', width: 190 },
        { text: 'Metadata', value: 'metadata' },
        { text: 'Actions', value: 'actions', sortable: false },
      ],
      editItem: null,
      editIndex: 0,
      showActivityUpdate: false,
      showMetadataUpdate: false,
      showNoteUpdate: false,
    }
  },
  mounted: function () {
    Api.get('/openc3-api/metadata').then((response) => {
      console.log(response.data)
      if (response.status !== 200) {
        this.metadata = []
      } else {
        this.metadata = response.data
      }
    })
  },
  computed: {
    inputError: function () {
      // Don't check for this.metadata.length < 1 because we have to allow for deletes
      const emptyKeyValue = this.metadata.find(
        (meta) => meta.key === '' || meta.value === ''
      )
      if (emptyKeyValue) {
        return 'Missing or empty key, value in the metadata table.'
      }
      return null
    },
    show: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
  },
  methods: {
    logFormat(date) {
      return format(new Date(date * 1000), 'yyyy-MM-dd HH:mm:ss.SSS')
    },
    metadataFormat(event) {
      let rows = []
      Object.entries(event.metadata).forEach(([key, value]) =>
        rows.push(`${key} => ${value}`)
      )
      return rows.join(', ')
    },
    deleteAction(item) {
      console.log(item)
      let deleteIndex = this.metadata.findIndex((element) => {
        return element.start === item.start
      })
      console.log(deleteIndex)
      this.$dialog
        .confirm(
          `Are you sure you want to remove ${item.type} at ${this.logFormat(
            item.start
          )}`,
          {
            okText: 'Delete',
            cancelText: 'Cancel',
          }
        )
        .then((dialog) => {
          this.metadata.splice(deleteIndex, 1)
          return Api.delete(`/openc3-api/metadata/${item.start}`)
        })
        .then((response) => {
          this.$emit('update')
          this.$notify.normal({
            title: `Deleted ${item.type}`,
            body: `Deleted ${item.type} at ${this.logFormat(item.start)}`,
          })
          this.$emit('close')
        })
        .catch((error) => {
          // TODO: It returns true on cancel?
        })
    },

    updateMetadata: function () {
      // const metadata = this.metadata.reduce((result, element) => {
      //   result[element.key] = element.value
      //   return result
      // }, {})
      // const color = '#003784'
      // Api.post('/openc3-api/metadata', {
      //   data: { color: color, metadata: metadata },
      // }).then((response) => {
      //   this.$notify.normal({
      //     title: 'Created Metadata',
      //     body: `Metadata created at ${response.data.start}`,
      //   })
      // })
      // this.$emit('response', metadata)
      this.show = !this.show
    },
    cancel: function () {
      this.$emit('response', 'Cancel')
      this.show = !this.show
    },
    updateValues: function (metaValues) {
      this.metadata = Object.keys(metaValues).map((k) => {
        return { key: k, value: metaValues[k] }
      })
    },
    newMetadata: function () {
      this.metadata.push({
        key: '',
        value: '',
      })
    },
    rm: function (index) {
      this.metadata.splice(index, 1)
    },
  },
}
</script>
