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
  <v-dialog
    :model-value="modelValue"
    max-width="900"
    @update:model-value="close"
  >
    <v-card>
      <v-card-title class="d-flex align-center">
        Repair Gap: {{ context.target }} {{ context.packet }}
        <v-spacer />
        <v-btn icon="mdi-close" variant="text" @click="close" />
      </v-card-title>
      <v-card-subtitle v-if="context.gap">
        {{ context.gap.start }} &mdash; {{ context.gap.end }} ({{
          context.gap.duration
        }})
      </v-card-subtitle>

      <v-card-text style="max-height: 75vh; overflow-y: auto">
        <div v-if="errorMessage" class="text-red monospace mb-4">
          Error: {{ errorMessage }}
        </div>

        <!-- Candidate listing phase -->
        <template v-if="!jobId">
          <div v-if="loadingCandidates" class="d-flex align-center mb-4">
            <v-progress-circular indeterminate size="24" class="mr-3" />
            Searching bucket for raw log files that cover this gap…
          </div>

          <template v-else>
            <div v-if="candidates.length === 0" class="text-medium-emphasis">
              No raw log files cover this gap window. Reingest is not available
              &mdash; the data may have been written from a source that skipped
              raw logging, or the logs have been deleted.
            </div>

            <template v-else>
              <div class="mb-2">
                {{ candidates.length }} raw log file(s) overlap this window.
                Select which to reingest:
              </div>
              <v-data-table
                v-model="selectedKeys"
                :headers="candidateHeaders"
                :items="candidates"
                item-value="key"
                show-select
                class="monospace"
                :items-per-page="20"
                density="compact"
                data-test="repair-candidates"
              />

              <div class="mt-4">
                <div class="text-subtitle-2 font-weight-bold mb-1">
                  Target Definition Version
                </div>
                <v-radio-group
                  v-model="targetVersion"
                  hide-details
                  density="compact"
                  data-test="repair-version"
                >
                  <v-radio
                    value="as_logged"
                    data-test="repair-version-as-logged"
                  >
                    <template #label>
                      <div style="padding-left: 10px">
                        <div>As logged (default)</div>
                        <div class="text-caption text-medium-emphasis">
                          Decode each file with the cmd/tlm definition that was
                          in effect when the data was originally logged. Safest
                          for historical fidelity — preserves packet layouts as
                          they existed at that time.
                        </div>
                        <div class="text-caption text-medium-emphasis mt-1">
                          If an item's type has changed since the log was
                          written (e.g. STRING &rarr; FLOAT), QuestDB column
                          types are kept as-is; historical values are cast to
                          fit the current column, and any values that can't cast
                          are stored as NULL.
                        </div>
                      </div>
                    </template>
                  </v-radio>
                  <v-radio value="current" data-test="repair-version-current">
                    <template #label>
                      <div style="padding-left: 10px">
                        <div>Current</div>
                        <div class="text-caption text-medium-emphasis">
                          Decode all files with the latest cmd/tlm definition.
                          Choose this when the historical definition had a bug
                          that you've since fixed, and you want the reingested
                          data decoded with the corrected layout.
                        </div>
                      </div>
                    </template>
                  </v-radio>
                </v-radio-group>
              </div>
            </template>
          </template>
        </template>

        <!-- Job polling phase -->
        <template v-else-if="jobStatus">
          <v-table density="compact" class="monospace mb-4">
            <tbody>
              <tr>
                <td class="font-weight-bold">Job</td>
                <td>{{ jobId }}</td>
              </tr>
              <tr>
                <td class="font-weight-bold">State</td>
                <td>{{ jobStatus.state }}</td>
              </tr>
              <tr>
                <td class="font-weight-bold">Phase</td>
                <td>{{ phaseLabel }}</td>
              </tr>
              <tr v-if="jobStatus.target_version">
                <td class="font-weight-bold">Target Version</td>
                <td>{{ jobStatus.target_version }}</td>
              </tr>
              <tr v-if="jobStatus.packets_written !== undefined">
                <td class="font-weight-bold">Packets Written</td>
                <td>{{ jobStatus.packets_written.toLocaleString() }}</td>
              </tr>
              <tr v-if="jobStatus.error">
                <td class="font-weight-bold text-red">Error</td>
                <td class="text-red">{{ jobStatus.error }}</td>
              </tr>
              <tr v-if="jobStatus.warnings && jobStatus.warnings.length">
                <td class="font-weight-bold text-orange">Warnings</td>
                <td class="text-orange">
                  <div v-for="(w, idx) in jobStatus.warnings" :key="idx">
                    {{ w }}
                  </div>
                </td>
              </tr>
            </tbody>
          </v-table>
          <v-progress-linear
            :model-value="progressPercent"
            :indeterminate="progressPercent === 0 && isRunning"
            class="mb-2"
          />
        </template>
      </v-card-text>

      <v-card-actions class="px-4 pb-4">
        <v-spacer />
        <v-btn
          v-if="!jobId"
          variant="text"
          :disabled="loadingCandidates"
          @click="close"
        >
          Cancel
        </v-btn>
        <v-btn
          v-if="!jobId"
          color="warning"
          variant="elevated"
          :disabled="
            loadingCandidates ||
            candidates.length === 0 ||
            selectedKeys.length === 0
          "
          data-test="repair-reingest"
          @click="startReingest"
        >
          Reingest {{ selectedKeys.length }}
        </v-btn>

        <v-btn
          v-if="jobId && !isRunning"
          color="primary"
          variant="elevated"
          data-test="repair-done"
          @click="finish"
        >
          Done
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { Api } from '@openc3/js-common/services'

const PHASE_LABELS = {
  downloading: 'Downloading files…',
  enabling_dedup: 'Enabling DEDUP…',
  ingesting: 'Ingesting packets…',
  dedup_cooldown: 'Waiting for DEDUP cooldown…',
  disabling_dedup: 'Disabling DEDUP…',
}

export default {
  props: {
    modelValue: {
      type: Boolean,
      default: false,
    },
    context: {
      type: Object,
      required: true,
    },
  },
  emits: ['update:modelValue', 'complete'],
  data() {
    return {
      loadingCandidates: false,
      candidates: [],
      selectedKeys: [],
      targetVersion: 'as_logged',
      bucketEnv: null,
      path: null,
      candidateHeaders: [
        { title: 'File', key: 'filename' },
        { title: 'Key', key: 'key' },
      ],
      jobId: null,
      jobStatus: null,
      pollHandle: null,
      errorMessage: null,
    }
  },
  computed: {
    isRunning() {
      if (!this.jobStatus) return false
      return ['Queued', 'Running'].includes(this.jobStatus.state)
    },
    phaseLabel() {
      const phase = this.jobStatus?.progress_phase
      if (!phase) return this.jobStatus?.state || ''
      if (phase === 'dedup_cooldown') {
        const remaining = this.cooldownRemaining
        if (remaining != null) {
          return `Waiting for DEDUP cooldown (${remaining}s)…`
        }
      }
      return PHASE_LABELS[phase] || phase
    },
    cooldownRemaining() {
      const enabledAt = this.jobStatus?.dedup_enabled_at
      const cooldown = this.jobStatus?.dedup_cooldown_seconds
      if (!enabledAt || !cooldown) return null
      const nowSec = Date.now() / 1000
      const enabledSec = new Date(enabledAt).getTime() / 1000
      const remaining = Math.round(enabledSec + cooldown - nowSec)
      return Math.max(remaining, 0)
    },
    progressPercent() {
      const s = this.jobStatus
      if (!s) return 0
      if (s.state === 'Complete') return 100
      if (!s.progress_total || s.progress_total === 0) return 0
      return Math.round((s.progress_current / s.progress_total) * 100)
    },
  },
  watch: {
    modelValue(open) {
      if (open) this.fetchCandidates()
    },
  },
  mounted() {
    if (this.modelValue) this.fetchCandidates()
  },
  beforeUnmount() {
    this.stopPolling()
  },
  methods: {
    close() {
      this.stopPolling()
      this.resetState()
      this.$emit('update:modelValue', false)
    },
    finish() {
      const completed = this.jobStatus?.state === 'Complete'
      this.close()
      if (completed) this.$emit('complete')
    },
    resetState() {
      this.candidates = []
      this.selectedKeys = []
      this.targetVersion = 'as_logged'
      this.bucketEnv = null
      this.path = null
      this.jobId = null
      this.jobStatus = null
      this.errorMessage = null
      this.loadingCandidates = false
    },
    async fetchCandidates() {
      this.resetState()
      this.loadingCandidates = true
      try {
        const response = await Api.get(
          '/openc3-api/storage/repair_candidates',
          {
            params: {
              scope: this.context.scope,
              target: this.context.target,
              packet: this.context.packet,
              cmd_or_tlm: this.context.cmdOrTlm,
              start_time: this.context.gap.startIso,
              end_time: this.context.gap.endIso,
            },
          },
        )
        this.candidates = response.data.files || []
        this.bucketEnv = response.data.bucket
        this.path = response.data.path
        this.selectedKeys = this.candidates.map((c) => c.key)
      } catch (error) {
        this.errorMessage = error.response?.data?.message || error.message
      } finally {
        this.loadingCandidates = false
      }
    },
    async startReingest() {
      this.errorMessage = null
      // The controller expects filenames relative to `path`, not full keys.
      const filenames = this.selectedKeys.map((key) => {
        if (this.path && key.startsWith(this.path)) {
          return key.slice(this.path.length)
        }
        return key.split('/').pop()
      })
      try {
        const response = await Api.post('/openc3-api/storage/reingest', {
          data: {
            scope: this.context.scope,
            bucket: this.bucketEnv,
            path: this.path,
            files: filenames,
            target_version: this.targetVersion,
          },
        })
        this.jobId = response.data.job_id
        this.jobStatus = { state: response.data.state }
        this.startPolling()
      } catch (error) {
        this.errorMessage = error.response?.data?.message || error.message
      }
    },
    startPolling() {
      this.stopPolling()
      this.pollHandle = setInterval(this.pollStatus, 2000)
      this.pollStatus()
    },
    stopPolling() {
      if (this.pollHandle) {
        clearInterval(this.pollHandle)
        this.pollHandle = null
      }
    },
    async pollStatus() {
      if (!this.jobId) return
      try {
        const response = await Api.get(
          `/openc3-api/storage/reingest/${this.jobId}`,
          { params: { scope: this.context.scope } },
        )
        this.jobStatus = response.data
        if (!this.isRunning) this.stopPolling()
      } catch (error) {
        this.errorMessage = error.response?.data?.message || error.message
        this.stopPolling()
      }
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
.text-orange {
  color: rgb(var(--v-theme-warning));
}
</style>
