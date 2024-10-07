<!--
# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <top-bar :title="title" :menus="menus" />
    <v-card width="100%">
      <div style="padding-left: 5px; padding-top: 5px">
        <span class="ma-2 font-size">Buckets:</span>
        <v-chip
          v-for="(bucket, index) in buckets"
          :key="index"
          color="primary"
          class="ma-2"
          @click.stop="selectBucket(bucket)"
        >
          <v-avatar start>
            <v-icon>mdi-bucket</v-icon>
          </v-avatar>
          {{ bucket }}
        </v-chip>
      </div>
      <div style="padding-left: 5px" v-if="volumes.length !== 0">
        <span class="ma-2 font-size">Volumes:</span>
        <v-chip
          v-for="(volume, index) in volumes"
          :key="index"
          color="primary"
          class="ma-2"
          @click.stop="selectVolume(volume)"
        >
          <v-avatar start>
            <v-icon>mdi-folder</v-icon>
          </v-avatar>
          {{ volume }}
        </v-chip>
      </div>
      <v-card-title style="padding-top: 0px">
        {{ root }} Files
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
        />
      </v-card-title>
      <v-data-table
        :headers="headers"
        :items="files"
        :search="search"
        :items-per-page="1000"
        :items-per-page-options="[1000]"
        :sort-by="{
          key: 'modified',
          order: 'desc',
        }"
        @click:row="fileClick"
        calculate-widths
        multi-sort
        dense
      >
        <template v-slot:top>
          <v-row
            class="ma-0"
            style="background-color: var(--color-background-surface-header)"
          >
            <v-btn icon>
              <v-icon @click="backArrow">mdi-chevron-left-box-outline</v-icon>
            </v-btn>
            <span class=".text-body-1 ma-2 font-size" data-test="file-path"
              >/{{ path }}</span
            >
            <v-spacer />
            <div class="pa-1 font-size">
              Folder Size: {{ folderTotal }}
              <span class="small-font-size">(not recursive)</span>
            </div>

            <v-spacer />
            <div style="display: flex" v-if="mode === 'bucket'">
              <span class="pa-1 font-size">Upload File</span>
              <v-file-input
                v-model="file"
                hide-input
                hide-details
                class="file-input"
                prepend-icon="mdi-upload"
                data-test="upload-file"
              />
            </div>
          </v-row>
        </template>
        <template v-slot:item.name="{ item }">
          <v-icon class="mr-2">{{ item.icon }}</v-icon
          >{{ item.name }}
        </template>
        <template v-slot:item.size="{ item }">
          {{ item.size ? item.size.toLocaleString() : '' }}
        </template>
        <template v-slot:item.action="{ item }">
          <v-icon
            class="mr-3"
            v-if="item.icon === 'mdi-file'"
            @click="downloadFile(item.name)"
            data-test="download-file"
            >mdi-download-box</v-icon
          >
          <v-icon
            v-if="item.icon === 'mdi-file'"
            @click="deleteFile(item.name)"
            data-test="delete-file"
            >mdi-delete</v-icon
          >
        </template>
      </v-data-table>
    </v-card>
    <v-dialog v-model="uploadPathDialog" max-width="600">
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span> Upload Path </span>
          <v-spacer />
        </v-system-bar>
        <v-card-text>
          <div class="mx-1">
            <v-row class="my-2">
              <span
                >This file path can be modified. New directories will be
                automatically created.</span
              >
              <v-text-field
                v-model="uploadFilePath"
                hide-details
                label="File Path"
                data-test="upload-file-path"
              />
            </v-row>
            <v-row>
              <v-spacer />
              <v-btn
                @click="uploadPathDialog = false"
                variant="outlined"
                class="mx-2"
                data-test="upload-file-cancel-btn"
              >
                Cancel
              </v-btn>
              <v-btn
                @click.prevent="uploadFile"
                class="mx-2"
                color="primary"
                type="submit"
                data-test="upload-file-submit-btn"
              >
                Upload
              </v-btn>
            </v-row>
          </div>
        </v-card-text>
      </v-card>
    </v-dialog>
    <v-dialog
      v-model="optionsDialog"
      @keydown.esc="optionsDialog = false"
      max-width="300"
    >
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span>Options</span>
          <v-spacer />
        </v-system-bar>
        <v-card-text>
          <div class="pa-3">
            <v-text-field
              min="1"
              max="3600"
              step="100"
              type="number"
              label="Refresh Interval (s)"
              :value="refreshInterval"
              @change="refreshInterval = $event"
              data-test="refresh-interval"
            />
          </div>
        </v-card-text>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import TopBar from '@openc3/tool-common/src/components/TopBar'
import Api from '@openc3/tool-common/src/services/api'
import axios from 'axios'

export default {
  components: {
    TopBar,
  },
  data() {
    return {
      title: 'Bucket Explorer',
      search: '',
      root: '',
      mode: 'bucket',
      buckets: [],
      volumes: [],
      uploadPathDialog: false,
      optionsDialog: false,
      refreshInterval: 60,
      updater: null,
      path: '',
      file: null,
      files: [],
      headers: [
        { text: 'Name', value: 'name' },
        { text: 'Size', value: 'size' },
        { text: 'Modified Date', value: 'modified' },
        { text: 'Action', value: 'action' },
      ],
      menus: [
        {
          label: 'File',
          items: [
            {
              label: 'Options',
              icon: 'mdi-cog',
              command: () => {
                this.optionsDialog = true
              },
            },
          ],
        },
      ],
    }
  },
  computed: {
    folderTotal() {
      return this.files
        .reduce((a, b) => a + (b.size ? b.size : 0), 0)
        .toLocaleString()
    },
  },
  created() {
    Api.get('/openc3-api/storage/buckets').then((response) => {
      this.buckets = response.data
    })
    Api.get('/openc3-api/storage/volumes').then((response) => {
      this.volumes = response.data
    })
    if (this.$route.params.path) {
      let parts = this.$route.params.path.split('/')
      if (parts[0] === '') {
        this.mode = 'volume'
        // Prepend the slash to note this is a volume not a bucket
        this.root = `/${parts[1]}`
        this.path = parts.slice(2).join('/')
      } else {
        this.mode = 'bucket'
        this.root = parts[0]
        this.path = parts.slice(1).join('/')
      }
      this.updateFiles()
    }
    this.changeUpdater()
  },
  beforeUnmount() {
    this.clearUpdater()
  },
  watch: {
    // This is the upload function that is activated when the file gets set
    file: async function () {
      if (this.file === null) return
      this.uploadFilePath = `${this.path}${this.file.name}`
      this.uploadPathDialog = true
    },
    refreshInterval() {
      this.changeUpdater()
    },
  },
  methods: {
    update() {
      this.$router.push({
        name: 'Bucket Explorer',
        params: {
          path: `${this.root}/${this.path}`,
        },
      })
      this.updateFiles()
    },
    changeUpdater() {
      this.clearUpdater()
      this.updater = setInterval(() => {
        // need to be in a bucket/volume otherwise updateFiles gets mad
        if (this.root) {
          this.updateFiles()
        }
      }, this.refreshInterval * 1000)
    },
    clearUpdater() {
      if (this.updater != null) {
        clearInterval(this.updater)
        this.updater = null
      }
    },
    selectBucket(bucket) {
      if (this.root === bucket) return
      this.mode = 'bucket'
      this.root = bucket
      this.path = ''
      this.update()
    },
    selectVolume(volume) {
      if (this.root === volume) return
      this.mode = 'volume'
      this.root = volume
      this.path = ''
      this.update()
    },
    backArrow() {
      // Nothing to do if we're at the root so return
      if (this.path === '') return
      let parts = this.path.split('/')
      this.path = parts.slice(0, parts.length - 2).join('/')
      // Only append the last slash if we're not at the root
      // The root is 2 because it's the path before clicking back
      if (parts.length > 2) {
        this.path += '/'
      }
      this.update()
    },
    fileClick(event) {
      if (event.icon === 'mdi-folder') {
        if (this.root === '') {
          // initial root click
          this.root = event.name
        } else {
          this.path += `${event.name}/`
        }
        this.update()
      }
    },
    downloadFile(filename) {
      let root = this.root.toUpperCase()
      let api = 'download'
      if (this.mode === 'volume') {
        api = 'download_file'
        root = root.slice(1)
      }
      Api.get(
        `/openc3-api/storage/${api}/${encodeURIComponent(
          this.path,
        )}${filename}?${this.mode}=OPENC3_${root}_${this.mode.toUpperCase()}`,
      )
        .then((response) => {
          let href = null
          if (this.mode === 'bucket') {
            href = response.data.url
          } else {
            // Decode Base64 string
            const decodedData = window.atob(response.data.contents)
            // Create UNIT8ARRAY of size same as row data length
            const uInt8Array = new Uint8Array(decodedData.length)
            // Insert all character code into uInt8Array
            for (let i = 0; i < decodedData.length; ++i) {
              uInt8Array[i] = decodedData.charCodeAt(i)
            }
            const blob = new Blob([uInt8Array])
            href = URL.createObjectURL(blob)
          }
          // Make a link and then 'click' on it to start the download
          const link = document.createElement('a')
          link.href = href
          link.setAttribute('download', filename)
          link.click()
        })

        .catch((response) => {
          this.$notify.caution({
            title: `Unable to download file ${this.path}${filename} from bucket ${this.root}`,
          })
        })
    },
    async uploadFile() {
      this.uploadPathDialog = false
      // Ensure they didn't slap a '/' at the beginning
      if (this.uploadFilePath.startsWith('/')) {
        this.uploadFilePath = this.uploadFilePath.slice(1)
      }

      // Reassign data to presignedRequest for readability
      const { data: presignedRequest } = await Api.get(
        `/openc3-api/storage/upload/${encodeURIComponent(
          this.uploadFilePath,
        )}?bucket=OPENC3_${this.root.toUpperCase()}_BUCKET`,
      )
      // This pushes the file into storage by using the fields in the presignedRequest
      // See storage_controller.rb get_upload_presigned_request()
      const response = await axios({
        ...presignedRequest,
        data: this.file,
      })
      this.file = null
      this.path = this.uploadFilePath.split('/').slice(0, -1).join('/') + '/'
      this.updateFiles()
    },
    deleteFile(filename) {
      let root = this.root.toUpperCase()
      if (this.mode === 'volume') {
        root = root.slice(1)
      }
      this.$dialog
        .confirm(`Are you sure you want to delete: ${filename}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          return Api.delete(
            `/openc3-api/storage/delete/${encodeURIComponent(
              this.path,
            )}${filename}?${
              this.mode
            }=OPENC3_${root}_${this.mode.toUpperCase()}`,
          )
        })
        .then((response) => {
          this.updateFiles()
        })
    },
    updateFiles() {
      let root = this.root.toUpperCase()
      if (this.mode === 'volume') {
        root = root.slice(1)
      }
      Api.get(
        `/openc3-api/storage/files/OPENC3_${root}_${this.mode.toUpperCase()}/${
          this.path
        }`,
      )
        .then((response) => {
          this.files = response.data[0].map((bucket) => {
            return { name: bucket, icon: 'mdi-folder' }
          })
          this.files = this.files.concat(
            response.data[1].map((item) => {
              return {
                name: item.name,
                icon: 'mdi-file',
                size: item.size,
                modified: item.modified,
              }
            }),
          )
        })
        .catch((response) => {
          this.files = []
          if (response.data.message) {
            this.$notify.caution({
              title: response.data.message,
            })
          } else {
            this.$notify.caution({
              title: response.message,
            })
          }
        })
    },
  },
}
</script>

<style scoped>
.font-size {
  font-size: 1rem;
}
.small-font-size {
  font-size: 0.8rem;
}
.file-input {
  padding-top: 0px;
  margin-top: 0px;
}
</style>
