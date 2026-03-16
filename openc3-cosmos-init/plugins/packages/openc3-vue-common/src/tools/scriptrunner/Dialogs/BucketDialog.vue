<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" persistent width="800" @keydown.esc="cancelHandler">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span> Bucket Dialog </span>
        <v-spacer />
      </v-toolbar>
      <div class="pa-2">
        <v-card-text>
          <v-row>
            <span class="text-h6">{{ title }}</span>
          </v-row>
          <v-row v-if="message">
            <span class="ma-3" style="white-space: pre-line" v-text="message" />
          </v-row>
          <v-row class="my-2">
            <v-chip
              v-for="(bucket, index) in buckets"
              :key="index"
              :variant="selectedBucket === bucket ? 'elevated' : 'outlined'"
              color="primary"
              class="ma-2"
              data-test="bucket-chip"
              @click.stop="selectBucket(bucket)"
            >
              <v-icon start>mdi-bucket</v-icon>
              {{ bucket }}
            </v-chip>
          </v-row>
          <v-row v-if="selectedBucket" class="my-1">
            <v-col class="pa-0">
              <v-row
                class="ma-0 align-center"
                style="background-color: var(--color-background-surface-header)"
              >
                <v-btn
                  icon="mdi-chevron-left-box-outline"
                  variant="text"
                  density="compact"
                  class="ml-2"
                  data-test="bucket-nav-back"
                  aria-label="Navigate Back"
                  @click.stop="backArrow"
                />
                <div
                  class="ma-2"
                  style="font-size: 0.875rem"
                  data-test="bucket-path"
                >
                  {{ selectedBucket }}/<span
                    v-for="(part, index) in breadcrumbPath"
                    :key="index"
                    ><a
                      style="cursor: pointer"
                      @click.prevent="gotoPath(part.path)"
                      >{{ part.name }}</a
                    >/</span
                  >
                </div>
              </v-row>
              <v-text-field
                v-model="search"
                label="Search"
                prepend-inner-icon="mdi-magnify"
                clearable
                variant="outlined"
                density="compact"
                single-line
                hide-details
                class="mx-2 mt-2"
                data-test="bucket-search"
              />
              <v-list
                density="compact"
                class="bucket-file-list"
                data-test="bucket-file-list"
              >
                <v-list-item v-if="loading">
                  <v-progress-circular indeterminate size="20" class="mr-2" />
                  Loading...
                </v-list-item>
                <v-list-item
                  v-for="item in filteredFiles"
                  :key="item.name"
                  :class="{
                    'selected-file':
                      selectedFile === item.name && item.icon === 'mdi-file',
                  }"
                  :data-test="`bucket-item-${item.name}`"
                  @click="itemClick(item)"
                  @dblclick="itemDblClick(item)"
                >
                  <template #prepend>
                    <v-icon>{{ item.icon }}</v-icon>
                  </template>
                  <v-list-item-title>{{ item.name }}</v-list-item-title>
                  <template v-if="item.size" #append>
                    <span class="text-caption">{{
                      formatSize(item.size)
                    }}</span>
                  </template>
                </v-list-item>
                <v-list-item v-if="!loading && filteredFiles.length === 0">
                  <v-list-item-title class="text-caption text-grey">
                    No files found
                  </v-list-item-title>
                </v-list-item>
              </v-list>
            </v-col>
          </v-row>
        </v-card-text>
      </div>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn
          variant="outlined"
          data-test="bucket-cancel"
          @click="cancelHandler"
        >
          Cancel
        </v-btn>
        <v-btn
          variant="flat"
          data-test="bucket-ok"
          :disabled="!selectedFile"
          @click.prevent="submitHandler"
        >
          Ok
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  props: {
    title: {
      type: String,
      required: true,
    },
    message: {
      type: String,
      default: null,
    },
    modelValue: Boolean,
  },
  emits: ['update:modelValue', 'response'],
  data() {
    return {
      buckets: [],
      selectedBucket: null,
      path: '',
      files: [],
      selectedFile: null,
      search: '',
      loading: false,
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
    breadcrumbPath() {
      if (!this.path) return []
      const parts = this.path.split('/').filter((p) => !!p)
      return parts.map((part, index) => ({
        name: part,
        path: parts.slice(0, index + 1).join('/') + '/',
      }))
    },
    filteredFiles() {
      if (!this.search) return this.files
      const term = this.search.toLowerCase()
      return this.files.filter((f) => f.name.toLowerCase().includes(term))
    },
  },
  created() {
    Api.get('/openc3-api/storage/buckets').then((response) => {
      this.buckets = response.data
    })
  },
  methods: {
    formatSize(bytes) {
      if (bytes < 1024) return `${bytes} B`
      if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
    },
    selectBucket(bucket) {
      this.selectedBucket = bucket
      this.path = ''
      this.selectedFile = null
      this.updateFiles()
    },
    backArrow() {
      if (this.path === '') return
      const parts = this.path.split('/')
      this.path = parts.slice(0, -2).join('/')
      if (this.path) {
        this.path += '/'
      }
      this.selectedFile = null
      this.updateFiles()
    },
    gotoPath(path) {
      this.path = path
      this.selectedFile = null
      this.updateFiles()
    },
    itemClick(item) {
      if (item.icon === 'mdi-folder') {
        this.path += `${item.name}/`
        this.selectedFile = null
        this.updateFiles()
      } else {
        this.selectedFile = item.name
      }
    },
    itemDblClick(item) {
      if (item.icon === 'mdi-file') {
        this.selectedFile = item.name
        this.submitHandler()
      }
    },
    updateFiles() {
      this.loading = true
      const root = this.selectedBucket.toUpperCase()
      Api.get(`/openc3-api/storage/files/OPENC3_${root}_BUCKET/${this.path}`)
        .then((response) => {
          this.files = response.data[0].map((dir) => ({
            name: dir,
            icon: 'mdi-folder',
          }))
          this.files = this.files.concat(
            response.data[1].map((item) => ({
              name: item.name,
              icon: 'mdi-file',
              size: item.size,
            })),
          )
          this.loading = false
        })
        .catch(() => {
          this.files = []
          this.loading = false
        })
    },
    submitHandler() {
      this.$emit('response', {
        bucket: `OPENC3_${this.selectedBucket.toUpperCase()}_BUCKET`,
        path: `${this.path}${this.selectedFile}`,
        filename: this.selectedFile,
      })
    },
    cancelHandler() {
      this.$emit('response', 'COSMOS__CANCEL')
    },
  },
}
</script>

<style scoped>
.bucket-file-list {
  max-height: 300px;
  overflow-y: auto;
  border: 1px solid rgba(var(--v-border-color), var(--v-border-opacity));
  border-radius: 4px;
  margin-top: 8px;
}
.selected-file {
  background-color: rgba(var(--v-theme-primary), 0.15);
}
</style>
