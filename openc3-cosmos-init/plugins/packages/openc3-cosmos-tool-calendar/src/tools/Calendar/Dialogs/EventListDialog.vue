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
          :headers="eventHeaders"
          :items="localEvents"
          :search="search"
          sort-by="start"
        >
          <template v-slot:no-data>
            <span> No events </span>
          </template>
          <template v-slot:item.start="{ item }">
            {{ logFormat(item.start, utc) }}
          </template>
          <template v-slot:item.stop="{ item }">
            {{ logFormat(item.stop, utc) }}
          </template>
          <template v-slot:item.type="{ item }">
            {{ item.type.charAt(0).toUpperCase() + item.type.slice(1) }}
          </template>
          <template v-slot:item.data="{ item }">
            {{ dataFormat(item) }}
          </template>
          <template v-slot:item.actions="{ item }">
            <v-icon small class="mr-2" @click="editAction(item)">
              mdi-pencil
            </v-icon>
            <v-icon small @click="deleteAction(item)"> mdi-delete </v-icon>
          </template>
        </v-data-table>
      </v-card>
    </v-dialog>
    <activity-update-dialog
      v-model="showActivityUpdate"
      :activity="editItem"
      @update="updateActivity"
    />
    <metadata-update-dialog
      v-model="showMetadataUpdate"
      :metadata-obj="editItem"
      @update="updateMetadata"
    />
    <note-update-dialog
      v-model="showNoteUpdate"
      :note="editItem"
      @update="updateNote"
    />
  </div>
</template>

<script>
import Api from '@openc3/tool-common/src/services/api'
import TimeFilters from '@/tools/Calendar/Filters/timeFilters.js'
import DeleteItem from '@/tools/Calendar/Dialogs/DeleteItem.js'
import ActivityUpdateDialog from '@/tools/Calendar/Dialogs/ActivityUpdateDialog'
import MetadataUpdateDialog from '@/tools/Calendar/Dialogs/MetadataUpdateDialog'
import NoteUpdateDialog from '@/tools/Calendar/Dialogs/NoteUpdateDialog'

export default {
  components: {
    ActivityUpdateDialog,
    MetadataUpdateDialog,
    NoteUpdateDialog,
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
      localEvents: [...this.events],
      eventHeaders: [
        { text: 'Start', value: 'start', width: 190 },
        { text: 'Stop', value: 'stop', width: 190 },
        { text: 'Type', value: 'type' },
        { text: 'Data', value: 'data' },
        { text: 'Actions', value: 'actions', sortable: false },
      ],
      editItem: null,
      editIndex: 0,
      showActivityUpdate: false,
      showMetadataUpdate: false,
      showNoteUpdate: false,
    }
  },
  computed: {
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
    dataFormat(event) {
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
      return data
    },
    editAction(item) {
      this.editIndex = this.localEvents.findIndex((element) => {
        return element.type === item.type && element.start === item.start
      })
      switch (item.type) {
        case 'activity':
          this.editItem = item.activity
          this.showActivityUpdate = true
          break
        case 'metadata':
          this.editItem = item.metadata
          this.showMetadataUpdate = true
          break
        case 'note':
          this.editItem = item.note
          this.showNoteUpdate = true
          break
      }
    },
    deleteAction(item) {
      let deleteIndex = this.localEvents.findIndex((element) => {
        return element.type === item.type && element.start === item.start
      })
      let api = null
      let start = null
      switch (item.type) {
        case 'activity':
          api = 'activity'
          start = item.activity.start
          break
        case 'metadata':
          api = 'metadata'
          start = item.metadata.start
          break
        case 'note':
          api = 'notes'
          start = item.note.start
          break
      }

      this.$dialog
        .confirm(
          `Are you sure you want to remove ${item.type} at ${item.start}`,
          {
            okText: 'Delete',
            cancelText: 'Cancel',
          }
        )
        .then((dialog) => {
          this.localEvents.splice(deleteIndex, 1)
          return Api.delete(`/openc3-api/${api}/${start}`)
        })
        .then((response) => {
          this.$emit('update')
          this.$notify.normal({
            title: `Deleted ${item.type}`,
            body: `Deleted ${item.type} at ${start}`,
          })
          this.$emit('close')
        })
        .catch((error) => {
          // TODO: It returns true on cancel?
        })
    },
    updateActivity(item) {
      this.$emit('update')
      this.localEvents[this.editIndex].activity = item
    },
    updateMetadata(item) {
      this.$emit('update')
      this.localEvents[this.editIndex].metadata = item
    },
    updateNote(item) {
      this.$emit('update')
      this.localEvents[this.editIndex].note = item
    },
  },
}
</script>
