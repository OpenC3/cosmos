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
  <div>
    <v-dialog v-model="show" persistent width="80vw">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span v-if="newMetadata">Metadata</span><span v-else>Events</span>
          <v-spacer />
          <v-btn
            icon="mdi-close-box"
            variant="text"
            density="compact"
            data-test="close-metadata-icon"
            @click="close"
          />
        </v-toolbar>
        <v-card-title>
          <v-row class="pa-3">
            <span v-if="newMetadata">Metadata</span><span v-else>Events</span>
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
            />
          </v-row>
        </v-card-title>
        <v-data-table
          :headers="eventHeaders"
          :items="localEvents"
          :search="search"
        >
          <template #no-data>
            <span> No events </span>
          </template>
          <template #item.start="{ item }">
            {{ formatDateTime(item.start, timeZone) }}
          </template>
          <template #item.end="{ item }">
            {{ formatDateTime(item.end, timeZone) }}
          </template>
          <template #item.type="{ item }">
            {{ item.type.charAt(0).toUpperCase() + item.type.slice(1) }}
          </template>
          <template #item.data="{ item }">
            {{ dataFormat(item) }}
          </template>
          <template #item.actions="{ item }">
            <v-icon
              size="small"
              class="mr-2"
              data-test="edit-event"
              @click="editAction(item)"
            >
              mdi-pencil
            </v-icon>
            <v-icon
              size="small"
              data-test="delete-event"
              @click="deleteAction(item)"
            >
              mdi-delete
            </v-icon>
          </template>
        </v-data-table>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn variant="outlined" data-test="close-event-list" @click="close">
            Close
          </v-btn>
          <v-btn
            v-if="newMetadata"
            variant="flat"
            data-test="new-event"
            @click="showMetadataCreate = true"
          >
            New Metadata
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
    <!-- Edit existing events -->
    <activity-create-dialog
      v-if="showActivityUpdate"
      v-model="showActivityUpdate"
      :activity="editActivity"
      :time-zone="timeZone"
      @update="updateActivity"
    />
    <metadata-create-dialog
      v-if="showMetadataUpdate"
      v-model="showMetadataUpdate"
      :metadata="editMetadata"
      :time-zone="timeZone"
      @update="updateMetadata"
    />
    <note-create-dialog
      v-if="showNoteUpdate"
      v-model="showNoteUpdate"
      :note="editNote"
      :time-zone="timeZone"
      @update="updateNote"
    />
    <!-- Create new metadata -->
    <metadata-create-dialog
      v-if="showMetadataCreate"
      v-model="showMetadataCreate"
      :time-zone="timeZone"
      @update="addMetadata"
    />
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import { TimeFilters } from '@/util'
import ActivityCreateDialog from './ActivityCreateDialog.vue'
import DeleteItem from './DeleteItem'
import MetadataCreateDialog from './MetadataCreateDialog.vue'
import NoteCreateDialog from './NoteCreateDialog.vue'

export default {
  components: {
    ActivityCreateDialog,
    MetadataCreateDialog,
    NoteCreateDialog,
  },
  mixins: [TimeFilters, DeleteItem],
  props: {
    events: {
      type: Array,
      required: true,
    },
    modelValue: {
      type: Boolean,
      required: true,
    },
    timeZone: {
      type: String,
      required: true,
    },
    types: {
      type: Array,
    },
    newMetadata: {
      type: Boolean,
      default: false,
    },
  },
  data() {
    return {
      search: '',
      localEvents: [...this.events],
      eventHeaders: [
        { title: 'Start', key: 'start', width: 215 },
        { title: 'Stop', key: 'end', width: 215 },
        { title: 'Type', key: 'type' },
        { title: 'Data', key: 'data' },
        { title: 'Actions', key: 'actions', sortable: false },
      ],
      editActivity: { start: new Date(), end: new Date() },
      editMetadata: { start: new Date(), end: new Date() },
      editNote: { start: new Date(), end: new Date() },
      editIndex: 0,
      showActivityUpdate: false,
      showMetadataUpdate: false,
      showNoteUpdate: false,
      showMetadataCreate: false,
    }
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
  created: function () {
    // TODO: Switch to vue3 syntax
    // this.$on('delete', (item) => {
    //   let index = this.localEvents.findIndex((element) => {
    //     return element.type === item.type && element.start === item.start
    //   })
    //   this.localEvents.splice(index, 1)
    // })
  },
  methods: {
    close() {
      this.$emit('close')
      this.show = false
    },
    dataFormat(event) {
      let data = event.name
      switch (event.type) {
        case 'note':
          data = event.note.description
          break
        case 'metadata':
          let rows = []
          Object.entries(event.metadata.metadata).forEach(([key, value]) =>
            rows.push(`${key}: ${value}`),
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
          this.editActivity = item.activity
          this.showActivityUpdate = true
          break
        case 'metadata':
          this.editMetadata = item.metadata
          this.showMetadataUpdate = true
          break
        case 'note':
          this.editNote = item.note
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
      let uuid = null
      switch (item.type) {
        case 'activity':
          api = `timeline/${item.activity.name}/activity`
          start = item.activity.start
          uuid = item.activity.uuid
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
          },
        )
        .then((dialog) => {
          this.localEvents.splice(deleteIndex, 1)
          let url = `/openc3-api/${api}/${start}`
          if (uuid) {
            url += `/${uuid}`
          }
          return Api.delete(url)
        })
        .then((response) => {
          this.$emit('update')
          this.$notify.normal({
            title: `Deleted ${item.type}`,
            body: `Deleted ${item.type} at ${start}`,
          })
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
    addMetadata(item) {
      // TODO: This is how Calendar creates new metadata items via makeMetadataEvent
      let metadata = {
        name: 'Metadata',
        start: new Date(item.start * 1000),
        end: new Date(item.start * 1000),
        color: item.color,
        type: item.type,
        timed: true,
        metadata: item,
      }
      this.localEvents.push(metadata)
    },
  },
}
</script>
