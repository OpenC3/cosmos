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
    <v-row no-gutters align="center" style="padding-left: 10px">
      <v-col cols="3">
        <v-btn
          block
          color="primary"
          data-test="toolAdd"
          @click="add()"
          :disabled="!name || !url || !icon"
        >
          Add
          <v-icon end theme="dark">{{ icon }}</v-icon>
        </v-btn>
      </v-col>
      <v-col cols="3">
        <v-text-field v-model="icon" label="Tool Icon" class="px-2" />
      </v-col>
      <v-col cols="3">
        <v-text-field v-model="name" label="Tool Name" class="px-2" />
      </v-col>
      <v-col cols="3" class="px-2">
        <v-text-field v-model="url" label="Tool Url" />
      </v-col>
    </v-row>
    <span class="text-body1 pa-3"
      >Drag and drop to reorder tools in the NavBar. Note: 'Base' and 'Admin'
      can't be reordered. A browser refresh is required to see the new tool
      order.</span
    >
    <v-list class="list" data-test="toolList" id="toollist">
      <div v-for="(tool, index) in tools" :key="tool">
        <v-list-item
          :class="{ filter: tool === 'Base' || tool === 'Admin' }"
          prepend-icon="mdi-drag-horizontal"
        >
          <v-list-item-title>{{ tool }}</v-list-item-title>

          <template v-slot:append>
            <v-tooltip location="bottom">
              <template v-slot:activator="{ props }">
                <v-icon v-bind="props" @click="editTool(tool)">
                  mdi-pencil
                </v-icon>
              </template>
              <span>Edit Tool</span>
            </v-tooltip>
            <v-tooltip location="bottom">
              <template v-slot:activator="{ props }">
                <v-icon v-bind="props" @click="deleteTool(tool)">
                  mdi-delete
                </v-icon>
              </template>
              <span>Delete Tool</span>
            </v-tooltip>
          </template>
        </v-list-item>
        <v-divider v-if="index < tools.length - 1" :key="index" />
      </div>
    </v-list>
    <output-dialog
      v-model="showDialog"
      v-if="showDialog"
      :content="jsonContent"
      type="Tool"
      :name="dialogTitle"
      @submit="dialogCallback"
    />
  </div>
</template>

<script>
import Api from '../../../services/api'
import OutputDialog from '../../../components/OutputDialog'
import Sortable from 'sortablejs'

export default {
  components: { OutputDialog },
  data() {
    return {
      name: null,
      icon: 'astro:add-small',
      url: null,
      tools: [],
      jsonContent: '',
      dialogTitle: '',
      showDialog: false,
      tool_id: null,
    }
  },
  mounted() {
    this.update()
    let el = document.getElementById('toollist')
    Sortable.create(el, {
      filter: '.filter', // 'filter' class is not draggable
      onUpdate: this.sortChanged,
    })
  },
  methods: {
    sortChanged(evt) {
      Api.post(`/openc3-api/tools/position/${this.tools[evt.oldIndex]}`, {
        data: {
          position: evt.newIndex,
        },
        // Tools are global and are always installed into the DEFAULT scope
        params: { scope: 'DEFAULT' },
      }).then((response) => {
        this.$notify.normal({
          title: `Reordered tool ${this.tools[evt.oldIndex]}`,
        })
        this.update()
      })
    },
    update() {
      // Tools are global and are always installed into the DEFAULT scope
      Api.get('/openc3-api/tools', { params: { scope: 'DEFAULT' } }).then(
        (response) => {
          this.tools = response.data
          this.name = ''
          this.url = ''
        },
      )
    },
    add() {
      Api.post('/openc3-api/tools', {
        data: {
          id: this.name,
          json: JSON.stringify({
            name: this.name,
            icon: this.icon,
            url: this.url,
            window: 'NEW',
          }),
        },
        // Tools are global and are always installed into the DEFAULT scope
        params: { scope: 'DEFAULT' },
      })
        .then((response) => {
          this.$notify.normal({
            title: `Added tool ${this.name}`,
          })
          this.update()
        })
        .catch((error) => {
          window.$cosmosNotify.serious({
            title: `Failed to add tool ${this.name}`,
            message: error.response.data,
          })
        })
    },
    editTool(name) {
      Api.get(`/openc3-api/tools/${name}`, {
        // Tools are global and are always installed into the DEFAULT scope
        params: { scope: 'DEFAULT' },
      }).then((response) => {
        this.tool_id = name
        this.jsonContent = JSON.stringify(response.data, null, '\t')
        this.dialogTitle = name
        this.showDialog = true
      })
    },
    dialogCallback(content) {
      this.showDialog = false
      if (content !== null) {
        let parsed = JSON.parse(content)
        let method = 'put'
        let url = `/openc3-api/tools/${this.tool_id}`
        if (parsed['name'] !== this.tool_id) {
          method = 'post'
          url = '/openc3-api/tools'
        }

        Api[method](url, {
          data: {
            json: content,
          },
          // Tools are global and are always installed into the DEFAULT scope
          params: { scope: 'DEFAULT' },
        }).then((response) => {
          this.$notify.normal({
            title: `Modified tool ${parsed['name']}`,
          })
          this.update()
        })
      }
    },
    deleteTool(name) {
      this.$dialog
        .confirm(`Are you sure you want to remove: ${name}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then(function (dialog) {
          return Api.delete(`/openc3-api/tools/${name}`, {
            // Tools are global and are always installed into the DEFAULT scope
            params: { scope: 'DEFAULT' },
          })
        })
        .then((response) => {
          this.$notify.normal({
            title: `Removed tool ${name}`,
          })
          this.update()
        })
    },
  },
}
</script>

<style scoped>
.list {
  background-color: var(--color-background-surface-default) !important;
  overflow-x: hidden;
}
</style>
