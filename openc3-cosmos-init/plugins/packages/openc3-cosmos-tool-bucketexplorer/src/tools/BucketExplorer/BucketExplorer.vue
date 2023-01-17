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
    <v-list>
      <span class="ma-2">Buckets (click to browse):</span>
      <v-list-item
        v-for="(bucket, index) in buckets"
        :key="index"
        @click.stop="selectBucket(bucket)"
      >
        <v-icon class="mr-2">mdi-bucket</v-icon
        ><v-list-item-title>{{ bucket }}</v-list-item-title>
      </v-list-item>
    </v-list>
    <v-card width="100%">
      <v-card-title>
        {{ bucket }} Files
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
          <v-icon class="ml-2" @click="backArrow"
            >mdi-chevron-left-box-outline</v-icon
          ><span class=".text-body-1 ma-2">{{ path }}</span>
        </template>
        <template v-slot:item.name="{ item }">
          <v-icon class="mr-2">{{ item.icon }}</v-icon
          >{{ item.name }}
        </template>
        <template v-slot:item.download="{ item }">
          <v-icon
            v-if="item.icon == 'mdi-file'"
            @click="downloadFile(item.name)"
            >mdi-download-box</v-icon
          >
        </template>
      </v-data-table>
    </v-card>
  </div>
</template>

<script>
import TopBar from '@openc3/tool-common/src/components/TopBar'
import Api from '@openc3/tool-common/src/services/api'

export default {
  components: {
    TopBar,
  },
  data() {
    return {
      title: 'COSMOS Bucket Explorer',
      search: '',
      bucket: '',
      buckets: [],
      path: '/',
      files: [],
      headers: [
        { text: 'Name', value: 'name' },
        { text: 'Size', value: 'size' },
        { text: 'Modified Date', value: 'modified' },
        { text: 'Download', value: 'download' },
      ],
    }
  },
  created() {
    Api.get('/openc3-api/storage/buckets').then((response) => {
      this.buckets = response.data
    })
    if (this.$route.params.path) {
      let parts = this.$route.params.path.split('/')
      this.bucket = parts[0]
      this.path = '/' + parts.slice(1).join('/')
      this.updateFiles()
    }
  },
  methods: {
    update() {
      this.$router.push({
        name: 'Bucket Explorer',
        params: {
          path: `${this.bucket}${this.path}`,
        },
      })
      this.updateFiles()
    },
    selectBucket(bucket) {
      this.bucket = bucket
      this.path = '/'
      this.update()
    },
    backArrow() {
      let parts = this.path.split('/')
      this.path = parts.slice(0, parts.length - 2).join('/') + '/'
      this.update()
    },
    fileClick(event) {
      if (event.icon === 'mdi-folder') {
        if (this.bucket === '') {
          // initial bucket click
          this.bucket = event.name
        } else {
          this.path += `${event.name}/`
        }
        this.update()
      }
    },
    downloadFile(filename) {
      Api.get(
        `/openc3-api/storage/download/${encodeURIComponent(
          this.path
        )}${filename}?bucket=OPENC3_${this.bucket.toUpperCase()}_BUCKET`
      )
        .then((response) => {
          // Make a link and then 'click' on it to start the download
          const link = document.createElement('a')
          link.href = response.data.url
          link.setAttribute('download', filename)
          link.click()
        })
        .catch((response) => {
          this.$notify.caution({
            title: `Unable to download file ${this.bucket}${this.path}${filename}`,
          })
        })
    },
    updateFiles() {
      Api.get(`/openc3-api/storage/files/${this.bucket}${this.path}`).then(
        (response) => {
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
                download: true,
              }
            })
          )
        }
      )
    },
  },
}
</script>
