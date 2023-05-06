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
  <div>
    <v-dialog v-model="show" width="80vw">
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span>Events</span>
          <v-spacer />
        </v-system-bar>
        <v-card-title>
          Events
          <v-spacer />
          <v-text-field
            v-model="search"
            append-icon="mdi-magnify"
            label="Search"
            single-line
            hide-details
          />
        </v-card-title>
        <v-data-table
          v-model="selected"
          :headers="eventHeaders"
          :items="listData"
          :search="search"
          sort-by="startStr"
        >
          <template v-slot:no-data>
            <span> No events </span>
          </template>
          <template v-slot:item.actions="{ item }">
            <v-icon small class="mr-2" @click="editItem(item)">
              mdi-pencil
            </v-icon>
            <v-icon small @click="deleteItem(item)" @delete="removeItem(item)">
              mdi-delete
            </v-icon>
          </template>
        </v-data-table>
      </v-card>
    </v-dialog>
    <metadata-update-dialog
      v-model="showMetadataUpdate"
      :metadata-obj="updateItem"
      @update="metadataUpdate"
    />
  </div>
</template>

<script>
import TimeFilters from '@/tools/Calendar/Filters/timeFilters.js'
import DeleteItem from '@/tools/Calendar/Dialogs/DeleteItem.js'
import MetadataUpdateDialog from '@/tools/Calendar/Dialogs/MetadataUpdateDialog'

export default {
  components: {
    MetadataUpdateDialog,
  },
  mixins: [TimeFilters, DeleteItem],
  props: {
    events: {
      type: Array,
      required: true,
    },
    utc: {
      type: Boolean,
      default: true,
    },
    value: {
      type: Boolean,
      required: true,
    },
    types: {
      type: Array,
    },
  },
  data() {
    return {
      search: '',
      selected: [],
      localEvents: [...this.events],
      eventHeaders: [
        { text: 'Start', value: 'startStr', width: 190 },
        { text: 'Stop', value: 'stopStr', width: 190 },
        { text: 'Type', value: 'typeStr' },
        { text: 'Data', value: 'data' },
        { text: 'Actions', value: 'actions', sortable: false },
      ],
      updateItem: null,
      editIndex: 0,
      showMetadataUpdate: false,
    }
  },
  computed: {
    listData: function () {
      if (!this.localEvents) return []
      return this.localEvents.map((event) => {
        let startStr = this.logFormat(event.start, this.utc)
        let stopStr = this.logFormat(event.end, this.utc)
        let data = event.name
        switch (event.type) {
          case 'note':
            data = event.note.description
            break
          case 'metadata':
            let rows = []
            Object.entries(event.metadata.metadata).forEach(([key, value]) =>
              rows.push(`${key} => ${value}`)
            )
            data = rows.join(', ')
            break
        }
        let typeStr = event.type.charAt(0).toUpperCase() + event.type.slice(1)
        return {
          startStr,
          stopStr,
          typeStr,
          data,
          ...event,
        }
      })
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
  created: function () {
    this.$on('delete', (item) => {
      let index = this.localEvents.findIndex((element) => {
        return element.type === item.type && element.start === item.start
      })
      this.localEvents.splice(index, 1)
    })
  },
  methods: {
    editItem(item) {
      this.editIndex = this.localEvents.findIndex((element) => {
        return element.type === item.type && element.start === item.start
      })
      switch (item.type) {
        case 'activity':
          break
        case 'metadata':
          this.updateItem = item.metadata
          this.showMetadataUpdate = true
          break
        case 'note':
          break
      }
      console.log(item)
    },
    metadataUpdate(item) {
      console.log(item)
      console.log(this.localEvents[this.editIndex])
      this.localEvents[this.editIndex].metadata = item
    },
  },
}
</script>
