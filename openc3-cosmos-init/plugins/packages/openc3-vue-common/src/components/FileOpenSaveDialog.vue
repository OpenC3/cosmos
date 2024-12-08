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
  <v-dialog v-model="show" width="600" scrollable @keydown.enter="success()">
    <v-card>
      <v-overlay :model-value="loading">
        <v-progress-circular
          indeterminate
          absolute
          size="64"
        ></v-progress-circular>
      </v-overlay>
      <form v-on:submit.prevent="success">
        <v-toolbar height="24">
          <v-spacer />
          <span> {{ title }} </span>
          <v-spacer />
        </v-toolbar>
        <v-card-text>
          <div class="pa-3">
            <v-row>{{ helpText }} </v-row>
            <v-row dense class="mt-5">
              <v-text-field
                v-model="search"
                flat
                autofocus
                hide-details
                clearable
                label="Search"
                prepend-inner-icon="mdi-magnify"
                density="compact"
                data-test="file-open-save-search"
              />
            </v-row>
            <v-row dense class="mt-2">
              <!-- return-object doesn't work until vuetify 3.7.3 -->
              <v-treeview
                v-model="tree"
                @update:activated="activeFile"
                density="compact"
                activatable
                ref="tree"
                style="width: 100%; max-height: 60vh; overflow: auto"
                item-value="id"
                :items="items"
                :search="search"
                :open-on-click="type === 'open'"
                :open-all="!!search"
              >
                <template v-slot:prepend="{ item, open }">
                  <v-icon v-if="!item.file">
                    {{ open ? 'mdi-folder-open' : 'mdi-folder' }}
                  </v-icon>
                  <v-icon v-else> {{ calcIcon(item.title) }} </v-icon>
                </template>
                <template v-slot:append="{ item }">
                  <!-- See ScriptRunner.vue const TEMP_FOLDER -->
                  <v-btn
                    v-if="item.title === '__TEMP__'"
                    icon
                    @click="deleteTemp"
                  >
                    <v-icon> mdi-delete </v-icon>
                  </v-btn>
                </template>
              </v-treeview>
            </v-row>
            <v-row class="my-2">
              <v-text-field
                v-model="selectedFile"
                hide-details
                label="Filename"
                data-test="file-open-save-filename"
                :disabled="type === 'open'"
              />
            </v-row>
            <v-row dense>
              <div
                class="my-2 text-red"
                style="white-space: pre-line"
                v-show="error"
              >
                {{ error }}
              </div>
            </v-row>
            <v-row class="mt-2">
              <v-spacer />
              <v-btn
                @click="show = false"
                variant="outlined"
                class="mx-2"
                data-test="file-open-save-cancel-btn"
                :disabled="disableButtons"
              >
                Cancel
              </v-btn>
              <v-btn
                @click.prevent="success"
                ref="submitBtn"
                type="submit"
                color="primary"
                class="mx-2"
                data-test="file-open-save-submit-btn"
                :disabled="disableButtons || !!error"
              >
                {{ submit }}
              </v-btn>
            </v-row>
          </div>
        </v-card-text>
      </form>
    </v-card>
  </v-dialog>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import { fileIcon } from '@/util/fileIcon'

export default {
  props: {
    type: {
      type: String,
      required: true,
      validator: function (value) {
        // The value must match one of these strings
        return ['open', 'save'].indexOf(value) !== -1
      },
    },
    apiUrl: String, // Base API URL for use with scripts or cmd-tlm
    requireTargetParentDir: Boolean, // Require that the save filename be nested in a directory with the name of a target
    inputFilename: String, // passed if this is a 'save' dialog
    modelValue: Boolean,
  },
  data() {
    return {
      tree: [],
      items: [],
      id: 1,
      search: null,
      selectedFile: null,
      disableButtons: false,
      targets: [],
      loading: true,
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
    title: function () {
      if (this.type === 'open') {
        return 'File Open'
      } else {
        return 'File Save As...'
      }
    },
    submit: function () {
      if (this.type === 'open') {
        return 'OPEN'
      } else {
        return 'SAVE'
      }
    },
    helpText: function () {
      if (this.type === 'open') {
        return 'Click on folders to open them and then click a file to select it before clicking Open. Use the search box to filter the results.'
      } else {
        return 'Click on the folder to save into. Then complete the filename path with the desired name. Use the search box to filter the results.'
      }
    },
    error: function () {
      if (this.selectedFile === '' || this.selectedFile === null) {
        return 'No file selected must select a file'
      }
      if (
        !this.selectedFile.match(this.validFilenameRegex) ||
        this.selectedFile.match(/\.\.|\/\/|\.\/|\/\./) // Block .'s and /'s next to each other (block path traversal)
      ) {
        let message = `${this.selectedFile} is not a valid filename. Must `
        if (this.requireTargetParentDir) {
          message += 'be in a target directory and '
        }
        message +=
          'only contain alphanumeric characters (including !-_.*) and a valid extension.\n\n' +
          'For example: TGT1/procedures/test.py or TGT2/lib/inst.rb'
        return message
      }
      if (this.type === 'save' && this.selectedFile.match(/\*$/)) {
        let message = `${this.selectedFile} is not a valid filename. Must not end in '*'.`
        return message
      }
      return null
    },
    validFilenameRegex: function () {
      const alphanumeric = '0-9a-zA-Z'
      const charset = `${alphanumeric}\\/\\!\\-\\_\\.\\*\\'\\(\\)` // From https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-keys.html a-z A-Z 0-9 / ! - _ . * ' ( )
      let expression = `[${charset}]+\\.[${alphanumeric}]+`
      if (this.requireTargetParentDir) {
        const targets = `(${this.targets.join('|')})`
        expression = `\\/?${targets}\\/${expression}`
      }
      return new RegExp(expression)
    },
  },
  created() {
    this.loadFiles()
    if (this.requireTargetParentDir) {
      Api.get('/openc3-api/targets').then((response) => {
        this.targets = response.data
        this.targets.push('__TEMP__') // Also support __TEMP__
      })
    }
  },
  methods: {
    calcIcon: function (filename) {
      return fileIcon(filename)
    },
    loadFiles: function () {
      Api.get(this.apiUrl)
        .then((response) => {
          this.items = []
          this.id = 1
          for (let file of response.data) {
            // Make a copy of the entire file path before calling insertFile
            // because insertFile does recursion and needs the original path
            this.filepath = file
            this.insertFile(this.items, 1, file)
            this.id++
          }
          if (this.inputFilename) {
            this.selectedFile = this.inputFilename
          }
          this.loading = false
        })
        .catch((error) => {
          this.$emit('error', `Failed to connect to OpenC3. ${error}`)
        })
    },
    clear: function () {
      this.show = false
      this.overwrite = false
      this.disableButtons = false
    },
    activeFile: function (file) {
      if (file.length === 0) {
        this.selectedFile = null
      } else {
        // This works when return-object is enabled
        // this.selectedFile = file[0].path

        // Search through items to find the item with id
        this.selectedFile = this.findItem(this.items, file[0])
        // Select the Submit button so return opens the file
        setTimeout(() => {
          this.$refs.submitBtn.$el.focus()
        }, 100)
      }
    },
    findItem: function (items, id) {
      for (let item of items) {
        if (item.id === id) {
          return item.path
        }
        if (item.children) {
          const found = this.findItem(item.children, id)
          if (found) {
            return found
          }
        }
      }
      return null
    },
    exists: function (root, name) {
      let found = false
      for (let item of root) {
        if (item.path === name) {
          return true
        }
        if (item.path.length > 1) {
          if (item.path[item.path.length - 1] === '*') {
            // Try without the star too
            if (item.path.slice(0, item.path.length - 1) === name) {
              return true
            }
          }
        }
        if (item.children) {
          found = found || this.exists(item.children, name)
        }
      }
      return found
    },
    success: function () {
      // Only process the success call if a file is selected and no error
      if (this.selectedFile !== null && this.error === null) {
        if (this.type === 'open') {
          this.openSuccess()
        } else {
          this.saveSuccess()
        }
      }
    },
    deleteTemp: function () {
      this.$dialog
        .confirm(`Are you sure you want to delete all the temporary files?`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          return Api.delete('/script-api/scripts/temp_files')
        })
        .then((response) => {
          this.$emit('clear-temp')
          this.loadFiles()
        })
        .catch((error) => {
          this.$notify.serious({
            title: 'Error',
            body: `Failed to remove script temporary files due to ${error}`,
          })
        })
    },
    openSuccess: function () {
      // Disable the buttons because the API call can take a bit
      this.disableButtons = true
      Api.get(`${this.apiUrl}/${this.selectedFile}`)
        .then((response) => {
          const file = {
            name: this.selectedFile,
            contents: response.data.contents,
          }
          if (response.data.suites) {
            file['suites'] = JSON.parse(response.data.suites)
          }
          if (response.data.error) {
            file['error'] = response.data.error
          }
          if (response.data.success) {
            file['success'] = response.data.success
          }
          const locked = response.data.locked
          const breakpoints = response.data.breakpoints
          this.$emit('file', { file, locked, breakpoints })
          this.clear()
        })
        .catch((error) => {
          this.$emit('error', `Failed to open ${this.selectedFile}. ${error}`)
          this.clear()
        })
    },
    saveSuccess: function () {
      const found = this.exists(this.items, this.selectedFile)
      if (found) {
        this.$dialog
          .confirm(`Are you sure you want to overwrite: ${this.selectedFile}`, {
            okText: 'Overwrite',
            cancelText: 'Cancel',
          })
          .then((dialog) => {
            this.$emit('filename', this.selectedFile)
            this.clear()
          })
          .catch((error) => {}) // Cancel, do nothing
      } else {
        this.$emit('filename', this.selectedFile)
        this.clear()
      }
    },
    insertFile: function (root, level, path) {
      let parts = path.split('/')
      // When there is only 1 part we're at the root so push the filename
      if (parts.length === 1) {
        root.push({
          id: this.id,
          title: parts[0],
          file: 'ruby',
          path: this.filepath,
        })
        this.id++
        return
      }
      // Look for the first part of the path
      const index = root.findIndex((item) => item.title === parts[0])
      if (index === -1) {
        // Name not found so push the item and add a children array
        root.push({
          id: this.id,
          title: parts[0],
          children: [],
          path: this.filepath.split('/').slice(0, level).join('/'),
        })
        this.id++
        this.insertFile(
          root[root.length - 1].children, // Start from the node we just added
          level + 1,
          parts.slice(1).join('/'), // Strip the first part of the path
        )
      } else {
        // We already have something at this level so recursively
        // call the insertPart using the node we found and adjust the path
        this.insertFile(
          root[index].children,
          level + 1,
          parts.slice(1).join('/'),
        )
      }
    },
  },
}
</script>
