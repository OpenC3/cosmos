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
                  <td :colspan="columns.length - 1">
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
                  <td>
                    <v-menu>
                      <template #activator="{ props }">
                        <v-icon
                          v-bind="props"
                          icon="mdi-dots-horizontal"
                          data-test="group-actions"
                        />
                      </template>
                      <v-list>
                        <v-list-item
                          title="Analyze Data Gaps"
                          prepend-icon="mdi-chart-timeline-variant-shimmer"
                          data-test="group-analyze-gap"
                          @click="analyzeGroupDataGap(item.items)"
                        />
                        <v-list-item
                          title="Delete All"
                          prepend-icon="mdi-delete"
                          data-test="group-delete"
                          @click="deleteGroup(item.items)"
                        />
                      </v-list>
                    </v-menu>
                  </td>
                </tr>
              </template>
              <template #item.diskSize="{ item }">
                {{ formatBytes(item.diskSize) }}
              </template>
              <template #item.rowCount="{ item }">
                {{ Number(item.rowCount).toLocaleString() }}
              </template>
              <template #item.actions="{ item }">
                <v-menu>
                  <template #activator="{ props }">
                    <v-icon
                      v-bind="props"
                      icon="mdi-dots-horizontal"
                      data-test="row-actions"
                    />
                  </template>
                  <v-list>
                    <v-list-item
                      title="Analyze Data Gap"
                      prepend-icon="mdi-chart-timeline-variant-shimmer"
                      data-test="row-analyze-gap"
                      @click="analyzeDataGap(item.tableName)"
                    />
                    <v-list-item
                      title="Delete"
                      prepend-icon="mdi-delete"
                      data-test="row-delete"
                      @click="deleteTable(item.tableName)"
                    />
                  </v-list>
                </v-menu>
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
                  <td :colspan="columns.length - 1">
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
                  <td>
                    <v-menu>
                      <template #activator="{ props }">
                        <v-icon
                          v-bind="props"
                          icon="mdi-dots-horizontal"
                          data-test="group-actions"
                        />
                      </template>
                      <v-list>
                        <v-list-item
                          title="Analyze Data Gaps"
                          prepend-icon="mdi-chart-timeline-variant-shimmer"
                          data-test="group-analyze-gap"
                          @click="analyzeGroupDataGap(item.items)"
                        />
                        <v-list-item
                          title="Delete"
                          prepend-icon="mdi-delete"
                          data-test="group-delete"
                          @click="deleteGroup(item.items)"
                        />
                      </v-list>
                    </v-menu>
                  </td>
                </tr>
              </template>
              <template #item.diskSize="{ item }">
                {{ formatBytes(item.diskSize) }}
              </template>
              <template #item.rowCount="{ item }">
                {{ Number(item.rowCount).toLocaleString() }}
              </template>
              <template #item.actions="{ item }">
                <v-menu>
                  <template #activator="{ props }">
                    <v-icon
                      v-bind="props"
                      icon="mdi-dots-horizontal"
                      data-test="row-actions"
                    />
                  </template>
                  <v-list>
                    <v-list-item
                      title="Analyze Data Gap"
                      prepend-icon="mdi-chart-timeline-variant-shimmer"
                      data-test="row-analyze-gap"
                      @click="analyzeDataGap(item.tableName)"
                    />
                    <v-list-item
                      title="Delete"
                      prepend-icon="mdi-delete"
                      data-test="row-delete"
                      @click="deleteTable(item.tableName)"
                    />
                  </v-list>
                </v-menu>
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

    <!-- Data Gap Analysis Dialog -->
    <v-dialog v-model="gapDialog" max-width="900">
      <v-card>
        <v-card-title class="d-flex align-center">
          Data Gap Analysis: {{ gapDialogTitle }}
          <v-spacer />
          <v-btn icon="mdi-close" variant="text" @click="gapDialog = false" />
        </v-card-title>
        <v-card-text style="max-height: 80vh; overflow-y: auto">
          <v-progress-linear
            v-if="gapLoading"
            :model-value="gapProgress"
            :indeterminate="gapProgress === 0"
            class="mb-4"
          />
          <div v-if="gapError" class="text-red monospace mb-4">
            Error: {{ gapError }}
          </div>

          <!-- Single table result -->
          <template v-if="!gapLoading && !gapError && gapSummary">
            <v-table density="compact" class="monospace mb-4">
              <tbody>
                <tr>
                  <td class="font-weight-bold">First Record</td>
                  <td>{{ gapSummary.firstTs }}</td>
                </tr>
                <tr>
                  <td class="font-weight-bold">Last Record</td>
                  <td>{{ gapSummary.lastTs }}</td>
                </tr>
                <tr>
                  <td class="font-weight-bold">Total Time Span</td>
                  <td>{{ gapSummary.timeSpan }}</td>
                </tr>
                <tr>
                  <td class="font-weight-bold">Gaps Found</td>
                  <td>{{ gapSummary.gaps.length }}</td>
                </tr>
              </tbody>
            </v-table>
            <div v-if="gapSummary.gaps.length">
              <h4 class="text-subtitle-1 font-weight-bold mb-2">
                Data Gaps (periods with no data)
              </h4>
              <v-data-table
                :headers="gapHeaders"
                :items="gapSummary.gaps"
                class="monospace"
                :items-per-page="20"
                density="compact"
              />
            </div>
            <div v-else class="text-medium-emphasis">
              No data gaps detected (sampled at 1 minute intervals).
            </div>
          </template>

          <!-- Group results (only tables with gaps) -->
          <template v-if="!gapLoading && !gapError && gapGroupResults">
            <div
              v-if="gapGroupResults.withGaps.length === 0"
              class="text-medium-emphasis"
            >
              No data gaps detected across {{ gapGroupResults.totalTables }}
              tables (sampled at 1 minute intervals).
            </div>
            <div v-else>
              <div class="mb-4 text-medium-emphasis">
                {{ gapGroupResults.withGaps.length }} of
                {{ gapGroupResults.totalTables }} tables have data gaps.
              </div>
              <div
                v-for="result in gapGroupResults.withGaps"
                :key="result.tableName"
                class="mb-6"
              >
                <h4 class="text-subtitle-1 font-weight-bold mb-1">
                  {{ result.packet }}
                </h4>
                <div class="text-medium-emphasis monospace mb-2">
                  {{ result.firstTs }} to {{ result.lastTs }} ({{
                    result.timeSpan
                  }}) &mdash; {{ result.gaps.length }} gap(s)
                </div>
                <v-data-table
                  :headers="gapHeaders"
                  :items="result.gaps"
                  class="monospace"
                  :items-per-page="10"
                  density="compact"
                />
              </div>
            </div>
          </template>
        </v-card-text>
      </v-card>
    </v-dialog>
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
        { title: 'Actions', key: 'actions', sortable: false },
      ],
      // Data gap dialog
      gapDialog: false,
      gapDialogTitle: '',
      gapLoading: false,
      gapProgress: 0,
      gapError: null,
      gapSummary: null,
      gapGroupResults: null,
      gapHeaders: [
        { title: 'Gap Start', key: 'start' },
        { title: 'Gap End', key: 'end' },
        { title: 'Duration', key: 'duration' },
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
      this.execSql(
        'SELECT tableName, partitionCount, rowCount, diskSize FROM table_storage;',
      )
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
    dropTable(tableName) {
      return this.execSql(`DROP TABLE '${tableName}';`)
    },
    deleteTable(tableName) {
      this.$dialog
        .confirm(`Are you sure you want to drop table: ${tableName}?`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then(() => {
          this.dropTable(tableName)
            .then(() => {
              this.metricsRows = this.metricsRows.filter(
                (row) => row.tableName !== tableName,
              )
            })
            .catch((error) => {
              if (error.response && error.response.data) {
                this.metricsError = error.response.data.message
              } else {
                this.metricsError = error.message
              }
            })
        })
    },
    deleteGroup(items) {
      const tableNames = items.map((item) => (item.raw || item).tableName)
      this.$dialog
        .confirm(
          `Are you sure you want to drop ${tableNames.length} tables?\n\n${tableNames.join('\n')}`,
          {
            okText: 'Delete',
            cancelText: 'Cancel',
          },
        )
        .then(() => {
          const nameSet = new Set(tableNames)
          Promise.all(tableNames.map((name) => this.dropTable(name)))
            .then(() => {
              this.metricsRows = this.metricsRows.filter(
                (row) => !nameSet.has(row.tableName),
              )
            })
            .catch((error) => {
              if (error.response && error.response.data) {
                this.metricsError = error.response.data.message
              } else {
                this.metricsError = error.message
              }
            })
        })
    },
    async execSql(sql, retries = 3) {
      for (let attempt = 1; attempt <= retries; attempt++) {
        try {
          return await Api.post('/openc3-api/tsdb/exec', {
            data: sql,
            headers: {
              Accept: 'application/json',
              'Content-Type': 'plain/text',
            },
          })
        } catch (error) {
          const msg = error.response?.data?.message || error.message || ''
          const isConnectionError =
            msg.includes('PQconsumeInput') ||
            msg.includes('server closed the connection')
          if (isConnectionError && attempt < retries) {
            await new Promise((r) => setTimeout(r, 1000 * attempt))
            continue
          }
          throw error
        }
      }
    },
    formatDuration(ms) {
      const seconds = Math.floor(ms / 1000)
      const days = Math.floor(seconds / 86400)
      const hours = Math.floor((seconds % 86400) / 3600)
      const minutes = Math.floor((seconds % 3600) / 60)
      const parts = []
      if (days) parts.push(`${days}d`)
      if (hours) parts.push(`${hours}h`)
      if (minutes) parts.push(`${minutes}m`)
      if (!parts.length) parts.push(`${seconds}s`)
      return parts.join(' ')
    },
    formatTimestamp(ts) {
      return new Date(ts).toISOString().replace('T', ' ').replace('.000Z', 'Z')
    },
    async fetchTableGaps(tableName) {
      // Get first and last timestamps
      const rangeResp = await this.execSql(
        `SELECT first(PACKET_TIMESECONDS) as first_ts, last(PACKET_TIMESECONDS) as last_ts FROM '${tableName}';`,
      )
      const rangeCols = rangeResp.data.columns
      const rangeRow = rangeResp.data.rows[0]
      const rangeObj = {}
      rangeCols.forEach((col, i) => {
        rangeObj[col] = rangeRow[i]
      })
      const firstTs = rangeObj.first_ts
      const lastTs = rangeObj.last_ts
      const totalMs = new Date(lastTs) - new Date(firstTs)

      // Sample by 1 minute with FILL(NULL) to detect gaps
      const gapResp = await this.execSql(
        `(SELECT PACKET_TIMESECONDS, count() as cnt FROM '${tableName}' SAMPLE BY 1m FILL(NULL)) WHERE cnt = null`,
      )
      const gapCols = gapResp.data.columns
      const gapRows = gapResp.data.rows.map((row) => {
        const obj = {}
        gapCols.forEach((col, i) => {
          obj[col] = row[i]
        })
        return obj
      })

      // Group contiguous null-minute timestamps into gaps.
      // Each row is a 1-minute bucket with no data. A time delta > 1 min
      // between consecutive rows means a new gap has started.
      const gaps = []
      if (gapRows.length > 0) {
        let gapStart = gapRows[0].PACKET_TIMESECONDS
        let gapEnd = gapStart
        for (let i = 1; i < gapRows.length; i++) {
          const prev = new Date(gapEnd)
          const curr = new Date(gapRows[i].PACKET_TIMESECONDS)
          if (curr - prev > 60_000) {
            gaps.push({
              start: this.formatTimestamp(gapStart),
              end: this.formatTimestamp(
                new Date(new Date(gapEnd).getTime() + 60_000),
              ),
              duration: this.formatDuration(
                new Date(gapEnd).getTime() + 60_000 - new Date(gapStart),
              ),
            })
            gapStart = gapRows[i].PACKET_TIMESECONDS
          }
          gapEnd = gapRows[i].PACKET_TIMESECONDS
        }
        gaps.push({
          start: this.formatTimestamp(gapStart),
          end: this.formatTimestamp(
            new Date(new Date(gapEnd).getTime() + 60_000),
          ),
          duration: this.formatDuration(
            new Date(gapEnd).getTime() + 60_000 - new Date(gapStart),
          ),
        })
      }

      return {
        firstTs: this.formatTimestamp(firstTs),
        lastTs: this.formatTimestamp(lastTs),
        timeSpan: this.formatDuration(totalMs),
        gaps,
      }
    },
    async analyzeDataGap(tableName) {
      this.gapDialogTitle = tableName
      this.gapDialog = true
      this.gapLoading = true
      this.gapProgress = 0
      this.gapError = null
      this.gapSummary = null
      this.gapGroupResults = null
      try {
        this.gapSummary = await this.fetchTableGaps(tableName)
      } catch (error) {
        this.gapError = error.response?.data?.message || error.message
      } finally {
        this.gapLoading = false
      }
    },
    async analyzeGroupDataGap(items) {
      const tableNames = items.map((item) => (item.raw || item).tableName)
      const target = (items[0].raw || items[0]).target
      this.gapDialogTitle = `${target} (${tableNames.length} tables)`
      this.gapDialog = true
      this.gapLoading = true
      this.gapProgress = 0
      this.gapError = null
      this.gapSummary = null
      this.gapGroupResults = null
      try {
        const withGaps = []
        for (let i = 0; i < tableNames.length; i++) {
          this.gapProgress = Math.round(((i + 1) / tableNames.length) * 100)
          try {
            const result = await this.fetchTableGaps(tableNames[i])
            if (result.gaps.length > 0) {
              const parts = tableNames[i].split('__')
              withGaps.push({
                tableName: tableNames[i],
                packet: parts[3] || tableNames[i],
                ...result,
              })
            }
          } catch {
            // Skip tables that error (e.g. empty tables)
          }
        }
        this.gapGroupResults = {
          totalTables: tableNames.length,
          withGaps,
        }
      } catch (error) {
        this.gapError = error.response?.data?.message || error.message
      } finally {
        this.gapLoading = false
      }
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
      this.execSql(this.sqlText)
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
