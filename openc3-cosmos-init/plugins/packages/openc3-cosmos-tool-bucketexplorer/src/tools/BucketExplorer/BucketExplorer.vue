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
          variant="elevated"
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
      <div v-if="volumes.length !== 0" style="padding-left: 5px">
        <span class="ma-2 font-size">Volumes:</span>
        <v-chip
          v-for="(volume, index) in volumes"
          :key="index"
          variant="elevated"
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
      <v-card-title
        class="pt-0 d-flex align-center justify-content-space-between"
      >
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
          data-test="search-input"
        />
      </v-card-title>
      <v-data-table
        v-model:sort-by="sortBy"
        :headers="headers"
        :items="files"
        :search="search"
        :items-per-page="-1"
        :items-per-page-options="[10, 20, 50, 100, -1]"
        multi-sort
        density="compact"
        hover
        @click:row.stop="fileClick"
      >
        <template #top>
          <v-row
            class="ma-0"
            style="background-color: var(--color-background-surface-header)"
          >
            <v-btn
              icon="mdi-chevron-left-box-outline"
              variant="text"
              density="compact"
              class="ml-3 mt-1"
              data-test="be-nav-back"
              aria-label="Navigate Back"
              @click.stop="backArrow"
            />
            <div class=".text-body-1 ma-2 font-size" data-test="file-path">
              <span v-for="(part, index) in breadcrumbPath" :key="index">
                /&nbsp;<a
                  style="cursor: pointer"
                  @click.prevent="gotoPath(part.path)"
                  >{{ part.name }}
                </a>
              </span>
            </div>
            <v-spacer />
            <div class="ma-2 font-size">
              Folder Size: {{ folderTotal }}
              <span class="small-font-size">(not recursive)</span>
            </div>

            <v-spacer />
            <div v-if="mode === 'bucket'" class="ma-2" style="display: flex">
              <span class="font-size">Upload File</span>
              <v-file-input
                v-model="file"
                hide-input
                hide-details
                class="mr-1 file-input"
                prepend-icon="mdi-upload"
                data-test="upload-file"
              />
            </div>
          </v-row>
        </template>
        <template #item.name="{ item }">
          <v-icon class="mr-2">{{ item.icon }}</v-icon>
          {{ item.name }}
        </template>
        <template #item.size="{ item }">
          {{ item.size ? item.size.toLocaleString() : '' }}
        </template>
        <template #item.action="{ item }">
          <v-btn
            v-if="item.icon === 'mdi-file' && isText(item.name)"
            icon="mdi-eye"
            variant="text"
            density="compact"
            class="mr-3"
            data-test="view-file"
            aria-label="View File"
            @click="viewFile(item.name)"
          />
          <v-btn
            v-if="item.icon === 'mdi-file'"
            icon="mdi-download-box"
            variant="text"
            density="compact"
            class="mr-3"
            data-test="download-file"
            aria-label="Download File"
            @click="downloadFile(item.name)"
          />
          <v-btn
            v-if="item.icon === 'mdi-file'"
            icon="mdi-delete"
            variant="text"
            density="compact"
            data-test="delete-file"
            aria-label="Delete File"
            @click="deleteFile(item.name)"
          />
        </template>
      </v-data-table>
    </v-card>
    <v-dialog v-model="uploadPathDialog" max-width="600">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span> Upload Path </span>
          <v-spacer />
        </v-toolbar>
        <v-card-text>
          <div class="mx-1">
            <v-row class="my-2">
              <span>
                This file path can be modified. New directories will be
                automatically created.
              </span>
            </v-row>
            <v-row>
              <v-text-field
                v-model="uploadFilePath"
                hide-details
                label="File Path"
                data-test="upload-file-path"
              />
            </v-row>
            <v-row class="mt-6">
              <v-spacer />
              <v-btn
                variant="outlined"
                class="mx-2"
                data-test="upload-file-cancel-btn"
                @click="uploadPathDialog = false"
              >
                Cancel
              </v-btn>
              <v-btn
                class="mx-2"
                color="primary"
                type="submit"
                data-test="upload-file-submit-btn"
                @click.prevent="uploadFile"
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
      max-width="300"
      @keydown.esc="optionsDialog = false"
    >
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span>Options</span>
          <v-spacer />
        </v-toolbar>
        <v-card-text>
          <div class="pa-3">
            <v-text-field
              v-model="refreshInterval"
              min="1"
              max="3600"
              step="100"
              type="number"
              label="Refresh Interval (s)"
              data-test="refresh-interval"
            />
          </div>
        </v-card-text>
      </v-card>
    </v-dialog>
    <output-dialog
      v-if="showDialog"
      v-model="showDialog"
      type="File"
      :content="dialogContent"
      :name="dialogName"
      :filename="dialogFilename"
      @submit="showDialog = false"
    />
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import { OutputDialog, TopBar } from '@openc3/vue-common/components'
import axios from 'axios'

export default {
  components: {
    TopBar,
    OutputDialog,
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
      updating: false,
      path: '',
      file: null,
      files: [],
      showDialog: false,
      dialogName: '',
      dialogContent: '',
      dialogFilename: '',
      sortBy: [
        {
          key: 'modified',
          order: 'desc',
        },
      ],
      headers: [
        {
          title: 'Name',
          value: 'name',
          sortable: true,
          nowrap: true,
        },
        {
          title: 'Size',
          value: 'size',
          sortable: true,
        },
        {
          title: 'ModifiedDate',
          value: 'modified',
          sortable: true,
        },
        {
          title: 'Action',
          value: 'action',
          align: 'end',
          nowrap: true,
        },
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
    breadcrumbPath() {
      const parts = this.path.split('/')
      return parts.map((part, index) => ({
        name: part,
        path: parts.slice(0, index + 1).join('/') + '/',
      }))
    },
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
  created() {
    Api.get('/openc3-api/storage/buckets').then((response) => {
      this.buckets = response.data
    })
    Api.get('/openc3-api/storage/volumes').then((response) => {
      this.volumes = response.data
    })
    if (this.$route.params.path?.length) {
      this.updating = true
      let parts = this.$route.params.path[0].split('/')
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
  methods: {
    isText(filename) {
      if (['Rakefile', 'Dockerfile'].includes(filename)) {
        return true
      }
      let ext = filename.split('.').pop()
      // Add some common COSMOS text file extensions
      return [
        'txt',
        'md',
        'rb',
        'py',
        'pyi',
        'cfg',
        'html',
        'js',
        'json',
        'info',
        'vue',
        'sh',
        'bat',
        'csv',
      ].includes(ext)
    },
    gotoPath(path) {
      if (!this.updating) {
        this.updating = true
        this.path = path
        this.update()
      }
    },
    update() {
      this.updating = true
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
      if (!this.updating) {
        this.updating = true
        this.mode = 'bucket'
        this.root = bucket
        this.path = ''
        this.update()
      }
    },
    selectVolume(volume) {
      if (!this.updating) {
        this.updating = true
        this.mode = 'volume'
        this.root = volume
        this.path = ''
        this.update()
      }
    },
    backArrow() {
      // Nothing to do if we're at the root so return
      if (this.path === '') return
      if (!this.updating) {
        this.updating = true
        let parts = this.path.split('/')
        this.path = parts.slice(0, parts.length - 2).join('/')
        // Only append the last slash if we're not at the root
        // The root is 2 because it's the path before clicking back
        if (parts.length > 2) {
          this.path += '/'
        }
        this.update()
      }
    },
    fileClick(_, { item }) {
      // Nothing to do if they click on a file
      if (item.icon !== 'mdi-folder') return
      if (!this.updating) {
        this.updating = true
        if (this.root === '') {
          // initial root click
          this.root = item.name
        } else {
          this.path += `${item.name}/`
        }
        this.update()
      }
    },
    viewFile(filename) {
      let root = this.root.toUpperCase()
      if (this.mode === 'volume') {
        root = root.slice(1)
      }
      Api.get(
        `/openc3-api/storage/download_file/${encodeURIComponent(
          this.path,
        )}${filename}?${this.mode}=OPENC3_${root}_${this.mode.toUpperCase()}`,
      ).then((response) => {
        this.dialogName = filename
        this.dialogFilename = filename
        // Decode Base64 string
        this.dialogContent = window.atob(response.data.contents)
        this.showDialog = true
      })
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
      let parts = this.uploadFilePath.split('/')
      if (parts.length > 1) {
        this.path = parts.slice(0, -1).join('/') + '/'
      } else {
        this.path = ''
      }
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
        .catch((err) => {})
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
          this.updating = false
        })
        .catch(({ response }) => {
          this.files = []
          if (response.data?.message) {
            this.$notify.caution({
              title: response.data.message,
            })
          } else {
            this.$notify.caution({
              title: response.message,
            })
          }
          this.updating = false
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
