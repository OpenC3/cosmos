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
    <top-bar :title="title" />
    <v-card width="100%">
      <div style="padding-left: 5px; padding-top: 5px">
        <span class="ma-2">Buckets:</span>
        <v-chip
          v-for="(bucket, index) in buckets"
          :key="index"
          color="primary"
          class="ma-2"
          @click.stop="selectBucket(bucket)"
        >
          <v-avatar left>
            <v-icon>mdi-bucket</v-icon>
          </v-avatar>
          {{ bucket }}
        </v-chip>
      </div>
      <div style="padding-left: 5px" v-if="volumes.length !== 0">
        <span class="ma-2">Volumes:</span>
        <v-chip
          v-for="(volume, index) in volumes"
          :key="index"
          color="primary"
          class="ma-2"
          @click.stop="selectVolume(volume)"
        >
          <v-avatar left>
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
          append-icon="mdi-magnify"
          label="Search"
          single-line
          hide-details
        />
      </v-card-title>
      <v-data-table
        :headers="headers"
        :items="files"
        :search="search"
        :items-per-page="1000"
        :footer-props="{
          showFirstLastPage: true,
          itemsPerPageOptions: [1000],
          firstIcon: 'mdi-page-first',
          lastIcon: 'mdi-page-last',
          prevIcon: 'mdi-chevron-left',
          nextIcon: 'mdi-chevron-right',
        }"
        @click:row="fileClick"
        calculate-widths
        multi-sort
        dense
      >
        <template v-slot:top>
          <v-row class="pa-5">
            <v-btn icon>
              <v-icon @click="backArrow">mdi-chevron-left-box-outline</v-icon>
            </v-btn>
            <span class=".text-body-1 ma-2" data-test="file-path"
              >/{{ path }}</span
            >
            <v-spacer />
            <div style="display: flex" v-if="mode === 'bucket'">
              <span class="pa-1">Upload</span>
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
      title: 'COSMOS Bucket Explorer',
      search: '',
      root: '',
      mode: 'bucket',
      buckets: [],
      volumes: [],
      path: '',
      file: null,
      files: [],
      headers: [
        { text: 'Name', value: 'name' },
        { text: 'Size', value: 'size' },
        { text: 'Modified Date', value: 'modified' },
        { text: 'Action', value: 'action' },
      ],
    }
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
  },
  watch: {
    // This is the upload function that is activated when the file gets set
    file: async function () {
      if (this.file === null) return
      // Reassign data to presignedRequest for readability
      const { data: presignedRequest } = await Api.get(
        `/openc3-api/storage/upload/${encodeURIComponent(
          `${this.path}${this.file.name}`
        )}?bucket=OPENC3_${this.root.toUpperCase()}_BUCKET`
      )
      // This pushes the file into storage by using the fields in the presignedRequest
      // See storage_controller.rb get_presigned_request()
      const response = await axios({
        ...presignedRequest,
        data: this.file,
      })
      this.file = null
      this.updateFiles()
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
          this.path
        )}${filename}?${this.mode}=OPENC3_${root}_${this.mode.toUpperCase()}`
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
              this.path
            )}${filename}?${
              this.mode
            }=OPENC3_${root}_${this.mode.toUpperCase()}`
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
        }`
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
            })
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
.file-input {
  padding-top: 0px;
  margin-top: 0px;
}
</style>
