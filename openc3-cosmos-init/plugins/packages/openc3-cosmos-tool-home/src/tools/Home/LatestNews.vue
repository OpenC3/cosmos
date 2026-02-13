<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div v-if="news.length">
    <div class="d-flex align-center ga-2 mb-5">
      <v-icon icon="mdi-newspaper-variant" size="20" color="secondary" />
      <span class="text-h6 text-white font-weight-bold">Latest News</span>
    </div>
    <div class="d-flex flex-column ga-4">
      <v-card
        v-for="item in news"
        :key="item.date"
        variant="outlined"
        rounded="lg"
        class="card pa-4"
      >
        <div class="d-flex align-baseline justify-space-between mb-2">
          <span class="text-body-1 font-weight-bold text-white">
            {{ item.title }}
          </span>
          <span class="text-caption text-medium-emphasis text-no-wrap ml-3">
            {{ formatDate(item.date) }}
          </span>
        </div>
        <!-- eslint-disable-next-line vue/no-v-html -->
        <div class="text-body-2 news-body" v-html="sanitize(item.body)" />
      </v-card>
    </div>
  </div>
</template>

<script>
import { Api, OpenC3Api } from '@openc3/js-common/services'
import DOMPurify from 'dompurify'

export default {
  data() {
    return {
      news: [],
      api: new OpenC3Api(),
    }
  },
  mounted() {
    this.api
      .get_setting('news_feed')
      .then((response) => {
        if (response) {
          this.fetchNews()
        }
      })
      .catch(() => {})
  },
  methods: {
    fetchNews() {
      Api.get('/openc3-api/news')
        .then(({ data }) => {
          this.news = data
            .sort((a, b) => Date.parse(b.date) - Date.parse(a.date))
            .slice(0, 3)
        })
        .catch(() => {})
    },
    formatDate(date) {
      return date.split('T')[0]
    },
    sanitize(html) {
      return DOMPurify.sanitize(html)
    },
  },
}
</script>

<style scoped>
.card {
  border-color: rgba(var(--v-theme-secondary), 0.2);
}
.news-body {
  color: rgba(255, 255, 255, 0.7);
  line-height: 1.5;
}
.news-body :deep(a) {
  color: rgb(var(--v-theme-secondary));
}
.news-body :deep(img) {
  max-width: 100%;
  border-radius: 4px;
}
</style>
