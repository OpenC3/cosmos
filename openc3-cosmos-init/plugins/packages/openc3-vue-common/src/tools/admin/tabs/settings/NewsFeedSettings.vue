<!--
# Copyright 2025 OpenC3, Inc.
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
  <v-card>
    <v-card-title>News Feed Settings</v-card-title>
    <v-alert v-model="errorLoading" type="error" closable density="compact">
      Error loading previous configuration due to {{ errorText }}
    </v-alert>
    <v-alert v-model="errorSaving" type="error" closable density="compact">
      Error saving due to {{ errorText }}
    </v-alert>
    <v-alert v-model="successSaving" type="success" closable density="compact">
      Saved! (Refresh the page to see changes)
    </v-alert>
    <v-card-text class="pb-0">
      <v-switch
        label="Allow COSMOS backend to pull the news feed from the COSMOS external news site.
        This is a low bandwidth poll which only happens every 12 hrs. To immediately update the news feed, click the 'Refresh' in the User Menu."
        v-model="newsFeed"
        color="primary"
      />
    </v-card-text>
    <v-card-actions>
      <v-btn
        @click="save"
        color="success"
        variant="text"
        data-test="save-news-feed"
      >
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import Settings from './settings.js'

const settingName = 'news_feed'
export default {
  mixins: [Settings],
  data() {
    return {
      newsFeed: true,
    }
  },
  created() {
    this.loadSetting(settingName)
  },
  methods: {
    save() {
      this.saveSetting(settingName, this.newsFeed)
      if (this.newsFeed) {
        this.api.update_news()
      }
    },
    parseSetting: function (response) {
      this.newsFeed = response
    },
  },
}
</script>
