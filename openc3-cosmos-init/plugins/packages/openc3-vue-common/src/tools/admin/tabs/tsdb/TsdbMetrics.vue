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
        <v-spacer />
        <v-text-field
          v-model="gapSampleInterval"
          label="Data Gap Sample Interval"
          hint="QuestDB SAMPLE BY duration (e.g. 5s, 1m, 10m, 1h)"
          persistent-hint
          density="compact"
          hide-details="auto"
          style="max-width: 260px"
          data-test="gap-sample-interval"
        />
      </v-card-actions>

      <div v-if="metricsRows.length">
        <template v-for="(section, idx) in sections" :key="section.title">
          <h3 class="text-h6 ml-2" :class="idx === 0 ? 'mt-4' : 'mt-6'">
            {{ section.title }}
          </h3>
          <v-data-table
            :headers="metricsHeaders"
            :items="section.items"
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
        </template>
      </div>
    </v-card>

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
              >
                <template #item.actions="{ item }">
                  <v-btn
                    v-if="isTlmTable(gapDialogTitle)"
                    icon="mdi-wrench"
                    size="small"
                    variant="text"
                    data-test="gap-repair"
                    title="Repair (reingest raw logs)"
                    @click="openRepair(item, gapDialogTitle)"
                  />
                </template>
              </v-data-table>
            </div>
            <div v-else class="text-medium-emphasis">
              No data gaps detected (sampled at {{ gapSampleInterval }}
              intervals).
            </div>
          </template>

          <!-- Group results (only tables with gaps) -->
          <template v-if="!gapLoading && !gapError && gapGroupResults">
            <div
              v-if="gapGroupResults.withGaps.length === 0"
              class="text-medium-emphasis"
            >
              No data gaps detected across
              {{ gapGroupResults.totalTables }} tables (sampled at
              {{ gapSampleInterval }} intervals).
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
                >
                  <template #item.actions="{ item }">
                    <v-btn
                      v-if="isTlmTable(result.tableName)"
                      icon="mdi-wrench"
                      size="small"
                      variant="text"
                      data-test="gap-repair"
                      title="Repair (reingest raw logs)"
                      @click="openRepair(item, result.tableName)"
                    />
                  </template>
                </v-data-table>
              </div>
            </div>
          </template>
        </v-card-text>
      </v-card>
    </v-dialog>

    <repair-gap-dialog
      v-if="repairContext"
      v-model="repairDialog"
      :context="repairContext"
      @complete="onRepairComplete"
    />
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import RepairGapDialog from './RepairGapDialog.vue'

export default {
  components: {
    RepairGapDialog,
  },
  data() {
    return {
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
        { title: 'Actions', key: 'actions', sortable: false, width: 80 },
      ],
      repairDialog: false,
      repairContext: null,
      gapSampleInterval: '1m',
    }
  },
  computed: {
    sections() {
      return [
        {
          title: 'Telemetry',
          items: this.metricsRows.filter((row) => row.type === 'TLM'),
        },
        {
          title: 'Commands',
          items: this.metricsRows.filter((row) => row.type === 'CMD'),
        },
      ]
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
      let target = tableName.split('__')[2] || tableName
      let packet = tableName.split('__')[3] || tableName
      this.$dialog
        .confirm(
          `Are you sure you want to drop table: ${tableName}? This removes ALL decommutated data for ${target} ${packet}!`,
          {
            okText: 'Delete',
            cancelText: 'Cancel',
          },
        )
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
      let target = tableNames[0].split('__')[2]
      this.$dialog
        .confirm(
          `Are you sure you want to drop ${tableNames.length} tables? This removes ALL decommutated data for ${target}!\n\n${tableNames.join('\n')}`,
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
              'Content-Type': 'text/plain',
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
    // Parse a QuestDB SAMPLE BY duration like "1m", "30s", "2h" into ms.
    // Returns null if malformed.
    parseSampleIntervalMs(input) {
      const match = String(input || '')
        .trim()
        .match(/^(\d+)\s*([smhd])$/i)
      if (!match) return null
      const value = Number.parseInt(match[1], 10)
      const multipliers = { s: 1_000, m: 60_000, h: 3_600_000, d: 86_400_000 }
      return value * multipliers[match[2].toLowerCase()]
    },
    async fetchTableGaps(tableName) {
      const interval = (this.gapSampleInterval || '1m').trim()
      const bucketMs = this.parseSampleIntervalMs(interval)
      if (!bucketMs) {
        throw new Error(
          `Invalid sample interval '${interval}'. Use a number followed by s, m, h, or d (e.g. 5s, 1m, 2h).`,
        )
      }

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

      // Sample by the user-chosen interval with FILL(NULL) to detect gaps.
      const gapResp = await this.execSql(
        `(SELECT PACKET_TIMESECONDS, count() as cnt FROM '${tableName}' SAMPLE BY ${interval} FILL(NULL)) WHERE cnt = null`,
      )
      const gapCols = gapResp.data.columns
      const gapRows = gapResp.data.rows.map((row) => {
        const obj = {}
        gapCols.forEach((col, i) => {
          obj[col] = row[i]
        })
        return obj
      })

      // Group contiguous null-bucket timestamps into gaps. A delta > bucketMs
      // between consecutive empty buckets means a new gap has started.
      const gaps = []
      const buildGap = (startRaw, endRaw) => {
        const startMs = new Date(startRaw).getTime()
        const endMs = new Date(endRaw).getTime() + bucketMs
        return {
          start: this.formatTimestamp(startRaw),
          end: this.formatTimestamp(new Date(endMs)),
          duration: this.formatDuration(endMs - startMs),
          // ISO strings avoid the JS precision cliff on nsec integers.
          startIso: new Date(startMs).toISOString(),
          endIso: new Date(endMs).toISOString(),
        }
      }
      if (gapRows.length > 0) {
        let gapStart = gapRows[0].PACKET_TIMESECONDS
        let gapEnd = gapStart
        for (let i = 1; i < gapRows.length; i++) {
          const prev = new Date(gapEnd)
          const curr = new Date(gapRows[i].PACKET_TIMESECONDS)
          if (curr - prev > bucketMs) {
            gaps.push(buildGap(gapStart, gapEnd))
            gapStart = gapRows[i].PACKET_TIMESECONDS
          }
          gapEnd = gapRows[i].PACKET_TIMESECONDS
        }
        gaps.push(buildGap(gapStart, gapEnd))
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
    // scope__TLM|CMD__TARGET__PACKET → { scope, cmdOrTlm, target, packet }
    parseTableName(tableName) {
      const parts = tableName.split('__')
      if (parts.length < 4) return null
      return {
        scope: parts[0],
        cmdOrTlm: parts[1],
        target: parts[2],
        packet: parts[3],
      }
    },
    isTlmTable(tableName) {
      const parsed = this.parseTableName(tableName)
      return parsed?.cmdOrTlm === 'TLM'
    },
    openRepair(gap, tableName) {
      const parsed = this.parseTableName(tableName)
      if (!parsed) return
      this.repairContext = {
        tableName,
        ...parsed,
        gap,
      }
      this.repairDialog = true
    },
    onRepairComplete() {
      // Re-run gap analysis on whichever view is currently showing.
      if (this.gapGroupResults) return // group analysis is expensive; let the user re-run manually
      if (this.gapDialogTitle) this.analyzeDataGap(this.gapDialogTitle)
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
