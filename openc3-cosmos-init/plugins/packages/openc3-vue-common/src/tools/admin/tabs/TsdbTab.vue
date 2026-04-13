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
    </v-tabs>

    <v-window v-model="activeTab">
      <!-- Metrics Tab -->
      <v-window-item value="metrics">
        <v-card>
          <v-card-title> QuestDB Table Storage Metrics </v-card-title>
          <v-card-text>
            <div v-if="metricsError" class="mt-2 text-red monospace">
              Error: {{ metricsError }}
            </div>
          </v-card-text>
          <v-card-actions class="px-2">
            <v-btn
              :loading="metricsLoading"
              color="success"
              variant="text"
              data-test="tsdb-metrics-refresh"
              @click="fetchMetrics"
            >
              Refresh
            </v-btn>
          </v-card-actions>

          <div v-if="metricsRows.length">
            <h3 class="text-h6 mt-4 ml-2">Telemetry</h3>
            <v-data-table
              :headers="metricsHeaders"
              :items="tlmRows"
              :group-by="metricsGroupBy"
              class="monospace"
              :items-per-page="50"
              density="compact"
            >
              <template
                #group-header="{ item, columns, toggleGroup, isGroupOpen }"
              >
                <tr>
                  <td :colspan="columns.length">
                    <v-btn
                      :icon="isGroupOpen(item) ? '$expand' : '$next'"
                      size="small"
                      variant="text"
                      @click="toggleGroup(item)"
                    />
                    <span class="font-weight-bold">
                      {{ item.value }}
                    </span>
                    <span class="ml-4 text-medium-emphasis">
                      Packets: {{ item.items.length }} &mdash; Rows:
                      {{ groupRowCount(item.items).toLocaleString() }} &mdash;
                      Disk: {{ formatBytes(groupDiskSize(item.items)) }}
                    </span>
                  </td>
                </tr>
              </template>
              <template #item.diskSize="{ item }">
                {{ formatBytes(item.diskSize) }}
              </template>
              <template #item.rowCount="{ item }">
                {{ Number(item.rowCount).toLocaleString() }}
              </template>
            </v-data-table>

            <h3 class="text-h6 mt-6 ml-2">Commands</h3>
            <v-data-table
              :headers="metricsHeaders"
              :items="cmdRows"
              :group-by="metricsGroupBy"
              class="monospace"
              :items-per-page="50"
              density="compact"
            >
              <template
                #group-header="{ item, columns, toggleGroup, isGroupOpen }"
              >
                <tr>
                  <td :colspan="columns.length">
                    <v-btn
                      :icon="isGroupOpen(item) ? '$expand' : '$next'"
                      size="small"
                      variant="text"
                      @click="toggleGroup(item)"
                    />
                    <span class="font-weight-bold">
                      {{ item.value }}
                    </span>
                    <span class="ml-4 text-medium-emphasis">
                      Packets: {{ item.items.length }} &mdash; Rows:
                      {{ groupRowCount(item.items).toLocaleString() }} &mdash;
                      Disk: {{ formatBytes(groupDiskSize(item.items)) }}
                    </span>
                  </td>
                </tr>
              </template>
              <template #item.diskSize="{ item }">
                {{ formatBytes(item.diskSize) }}
              </template>
              <template #item.rowCount="{ item }">
                {{ Number(item.rowCount).toLocaleString() }}
              </template>
            </v-data-table>
          </div>
        </v-card>
      </v-window-item>

      <!-- Queries Tab -->
      <v-window-item value="queries">
        <v-card>
          <v-card-title> Send SQL Queries to QuestDB </v-card-title>
          <v-card-subtitle>
            THIS IS DANGEROUS! This allows you to interact directly with the
            underlying QuestDB time series database, making it easy to modify or
            delete data.
            <br /><br />
            Enter SQL queries like:
            <code>
              SELECT * FROM DEFAULT__TLM__INST__HEALTH_STATUS LIMIT 10
            </code>
            or
            <code>SHOW TABLES</code>
          </v-card-subtitle>
          <v-card-text class="pb-0 ml-2">
            <v-textarea
              v-model="sqlText"
              hide-details
              label="SQL query"
              class="monospace"
              rows="3"
              @keydown="commandKeydown"
            />
            <div v-if="errorMessage" class="mt-2 text-red monospace">
              Error: {{ errorMessage }}
            </div>
          </v-card-text>
          <v-card-actions class="px-2">
            <v-btn
              :disabled="!sqlText.length"
              :loading="loading"
              color="success"
              variant="text"
              data-test="tsdb-execute"
              @click="executeQuery"
            >
              Execute
            </v-btn>
          </v-card-actions>

          <v-data-table
            v-if="columns.length"
            :headers="tableHeaders"
            :items="rows"
            class="monospace"
            :items-per-page="50"
            density="compact"
          >
          </v-data-table>
        </v-card>
      </v-window-item>
    </v-window>
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  data() {
    return {
      activeTab: 'metrics',
      // Metrics tab
      metricsRows: [],
      metricsError: null,
      metricsLoading: false,
      metricsGroupBy: [{ key: 'target', order: 'asc' }],
      metricsHeaders: [
        { title: 'Packet', key: 'packet' },
        { title: 'Table Name', key: 'tableName' },
        { title: 'Partition Count', key: 'partitionCount' },
        { title: 'Row Count', key: 'rowCount' },
        { title: 'Disk Size', key: 'diskSize' },
      ],
      // Queries tab
      sqlText: '',
      columns: [],
      rows: [],
      errorMessage: null,
      loading: false,
    }
  },
  computed: {
    tlmRows() {
      return this.metricsRows.filter((row) => row.type === 'TLM')
    },
    cmdRows() {
      return this.metricsRows.filter((row) => row.type === 'CMD')
    },
    tableHeaders() {
      return this.columns.map((col) => ({
        title: col,
        key: col,
      }))
    },
  },
  mounted() {
    this.fetchMetrics()
  },
  methods: {
    groupRowCount(items) {
      return items.reduce(
        (sum, row) => sum + Number((row.raw || row).rowCount || 0),
        0,
      )
    },
    groupDiskSize(items) {
      return items.reduce(
        (sum, row) => sum + Number((row.raw || row).diskSize || 0),
        0,
      )
    },
    formatBytes(bytes) {
      if (bytes === 0) return '0 B'
      const units = ['B', 'KB', 'MB', 'GB', 'TB']
      const k = 1024
      const i = Math.floor(Math.log(bytes) / Math.log(k))
      const value = bytes / Math.pow(k, i)
      return `${value.toFixed(i === 0 ? 0 : 1)} ${units[i]}`
    },
    fetchMetrics() {
      this.metricsError = null
      this.metricsRows = []
      this.metricsLoading = true
      const sql =
        'SELECT tableName, partitionCount, rowCount, diskSize FROM table_storage;'
      Api.post('/openc3-api/tsdb/exec', {
        data: sql,
        headers: {
          Accept: 'application/json',
          'Content-Type': 'plain/text',
        },
      })
        .then((response) => {
          const cols = response.data.columns
          this.metricsRows = response.data.rows.map((row) => {
            const obj = {}
            cols.forEach((col, i) => {
              obj[col] = row[i]
            })
            const parts = (obj.tableName || '').split('__')
            obj.type = parts[1] || ''
            obj.target = parts[2] || ''
            obj.packet = parts[3] || ''
            return obj
          })
        })
        .catch((error) => {
          if (error.response && error.response.data) {
            this.metricsError = error.response.data.message
          } else {
            this.metricsError = error.message
          }
        })
        .finally(() => {
          this.metricsLoading = false
        })
    },
    commandKeydown($event) {
      if (($event.metaKey || $event.ctrlKey) && $event.key === 'Enter') {
        this.executeQuery()
      }
    },
    executeQuery() {
      this.errorMessage = null
      this.columns = []
      this.rows = []
      this.loading = true
      Api.post('/openc3-api/tsdb/exec', {
        data: this.sqlText,
        headers: {
          Accept: 'application/json',
          'Content-Type': 'plain/text',
        },
      })
        .then((response) => {
          this.columns = response.data.columns
          this.rows = response.data.rows.map((row) => {
            const obj = {}
            this.columns.forEach((col, i) => {
              obj[col] = row[i]
            })
            return obj
          })
        })
        .catch((error) => {
          if (error.response && error.response.data) {
            this.errorMessage = error.response.data.message
          } else {
            this.errorMessage = error.message
          }
        })
        .finally(() => {
          this.loading = false
        })
    },
  },
}
</script>

<style scoped>
.monospace {
  font-family: monospace;
  font-size: 14px;
}
.text-red {
  color: rgb(var(--v-theme-error));
}
</style>
