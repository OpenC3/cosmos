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
  <v-card>
    <v-card-title> Send SQL Queries to QuestDB </v-card-title>
    <v-card-subtitle>
      THIS IS DANGEROUS! This allows you to interact directly with the
      underlying QuestDB time series database, making it easy to modify or
      delete data.
      <br /><br />
      Enter SQL queries like:
      <code> SELECT * FROM DEFAULT__TLM__INST__HEALTH_STATUS LIMIT 10 </code>
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
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  data() {
    return {
      sqlText: '',
      columns: [],
      rows: [],
      errorMessage: null,
      loading: false,
    }
  },
  computed: {
    tableHeaders() {
      return this.columns.map((col) => ({
        title: col,
        key: col,
      }))
    },
  },
  methods: {
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
