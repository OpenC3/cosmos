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
  <v-dialog v-model="show" width="600">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span> Download Gems </span>
        <v-spacer />
      </v-toolbar>
      <v-card-text>
        <div class="pa-3">
          <v-row class="my-2"> Select a download option </v-row>
          <v-row>
            <v-col>
              <div class="px-2">
                <v-btn
                  block
                  data-test="searchGithub"
                  color="primary"
                  :disabled="disableSearch"
                  @click="searchGithub"
                >
                  Github
                  <v-icon end theme="dark"> mdi-github </v-icon>
                </v-btn>
              </div>
            </v-col>
          </v-row>
          <!---
          <v-row>
            <v-col>
              <div class="px-2">
                <v-btn
                  @click="searchRuby"
                  block
                  data-test="searchRuby"
                  color="primary"
                  :disabled="disableSearch"
                >
                  RubyGems
                  <v-icon right dark> mdi-heart </v-icon>
                </v-btn>
              </div>
            </v-col>
          </v-row>
          --->
          <v-row class="mt-5"> Community Gems </v-row>
          <div v-if="listData.length < 1" class="mt-4">
            <v-row class="mx-2">
              <span> I’m sorry, Dave. No gems available.... </span>
            </v-row>
          </div>
          <div v-else class="mt-4">
            <div v-for="(data, index) in listData" :key="index">
              <v-list-item>
                <v-list-item-title>{{ data.name }}</v-list-item-title>

                <v-list-item icon>
                  <v-progress-circular
                    v-if="activeDownload"
                    indeterminate
                    color="primary"
                  />
                  <v-btn
                    v-else
                    icon="mdi-cloud-download"
                    variant="text"
                    :disabled="activeDownload"
                    @click="downloadGem(data)"
                  />
                </v-list-item>
              </v-list-item>
              <v-divider v-if="index < listData.length - 1" :key="index" />
            </div>
          </div>
        </div>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
// Directly use axios since we need no authentication or scope
import axios from 'axios'

export default {
  props: {
    modelValue: Boolean,
  },
  data() {
    return {
      url: '',
      type: null,
      response: null,
      activeDownload: false,
      disableSearch: false,
      expanded: [],
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
    listData: function () {
      if (!this.response) return []
      if (this.type === 'github') {
        return this.parseGithub()
      } else {
        return this.parseRuby()
      }
    },
  },
  methods: {
    parseGithub: function () {
      const gemRegEx = /\w+.gem/
      return this.response.tree
        .filter((f) => gemRegEx.exec(f.path))
        .map((f) => {
          return {
            name: f.path,
            url: `https://raw.github.com/OpenC3/openc3-tools/main/${f.path}`,
          }
        })
    },
    getResponse: function () {
      this.disableSearch = true
      axios.get(this.url).then((response) => {
        this.response = response.data
      })
      setTimeout(() => {
        this.disableSearch = false
      }, 10000)
    },
    searchGithub: function () {
      this.type = 'github'
      this.url =
        'https://api.github.com/repos/OpenC3/openc3-tools/git/trees/main?recursive=1'
      this.getResponse()
    },
    downloadGem: function (gem) {
      const link = document.createElement('a')
      link.href = gem.url
      link.setAttribute('download', gem.name)
      link.click()
      link.remove()
    },
  },
}
</script>
