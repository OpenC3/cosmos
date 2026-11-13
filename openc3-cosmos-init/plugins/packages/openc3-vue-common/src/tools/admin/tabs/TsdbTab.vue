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
  <div>
    <v-tabs v-model="activeTab">
      <v-tab value="metrics" data-test="tsdb-metrics-tab">Metrics</v-tab>
      <v-tab value="queries" data-test="tsdb-queries-tab">Queries</v-tab>
      <v-tab
        v-for="tab in extraTabs"
        :key="tab.value"
        :value="tab.value"
        :data-test="`tsdb-${tab.value}-tab`"
      >
        {{ tab.title }}
      </v-tab>
    </v-tabs>
    <v-window v-model="activeTab">
      <v-window-item value="metrics">
        <tsdb-metrics />
      </v-window-item>
      <v-window-item value="queries">
        <tsdb-queries />
      </v-window-item>
      <v-window-item
        v-for="tab in extraTabs"
        :key="tab.value"
        :value="tab.value"
      >
        <component :is="tab.component" />
      </v-window-item>
    </v-window>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import TsdbMetrics from './tsdb/TsdbMetrics.vue'
import TsdbQueries from './tsdb/TsdbQueries.vue'

// Additional sub-tabs: [{ value, title, component }]
defineProps({
  extraTabs: {
    type: Array,
    default: () => [],
  },
})

const activeTab = ref('metrics')
</script>
