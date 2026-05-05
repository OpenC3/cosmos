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
    fullscreen
    transition="dialog-bottom-transition"
    data-test="version-history-dialog"
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <v-card class="d-flex flex-column h-100">
      <v-card-title class="d-flex align-center flex-shrink-0">
        <span>Version History — {{ filename }}</span>
        <v-spacer />
        <v-btn
          icon="mdi-close"
          variant="text"
          aria-label="Close"
          data-test="version-history-close"
          @click="$emit('update:modelValue', false)"
        />
      </v-card-title>
      <v-divider />
      <v-card-text class="pa-0 flex-grow-1 overflow-hidden">
        <div v-if="loading" class="pa-6 text-center">
          <v-progress-circular indeterminate color="primary" />
        </div>
        <div v-else-if="loadError" class="pa-6">
          <v-alert type="error" variant="tonal">
            Failed to load versions: {{ loadError }}
          </v-alert>
        </div>
        <v-row v-else no-gutters class="h-100">
          <v-col cols="4" class="version-list-pane overflow-auto">
            <v-list density="compact" data-test="version-list">
              <v-list-item
                v-for="v in versions"
                :key="v.version_id"
                :active="selectedVersionId === v.version_id"
                @click="selectVersion(v.version_id)"
              >
                <template #prepend>
                  <v-icon
                    :color="
                      v.version_id === currentVersionId ? 'primary' : undefined
                    "
                  >
                    {{
                      v.version_id === currentVersionId
                        ? 'mdi-bookmark'
                        : 'mdi-bookmark-outline'
                    }}
                  </v-icon>
                </template>
                <v-list-item-title class="text-body-2">
                  <span class="text-truncate">{{
                    v.saved_by || 'unknown'
                  }}</span>
                  <span v-if="v.version_id === currentVersionId" class="ml-2">
                    <v-chip size="x-small" color="primary" variant="tonal">
                      Current
                    </v-chip>
                  </span>
                </v-list-item-title>
                <v-list-item-subtitle>
                  {{ formatTimestamp(v.last_modified || v.saved_at) }}
                  <v-chip
                    v-if="v.tainted"
                    size="x-small"
                    color="warning"
                    variant="tonal"
                    class="ml-1"
                  >
                    tainted
                  </v-chip>
                </v-list-item-subtitle>
                <div class="version-mini-badges mt-1 d-flex flex-wrap">
                  <v-chip
                    size="x-small"
                    :color="badgeColor('validated', v)"
                    :variant="badgeVariant('validated', v)"
                    class="mr-1"
                  >
                    Validated
                  </v-chip>
                  <v-chip
                    size="x-small"
                    :color="badgeColor('reviewed', v)"
                    :variant="badgeVariant('reviewed', v)"
                    class="mr-1"
                  >
                    {{ reviewedLabel(v) }}
                  </v-chip>
                  <v-chip
                    size="x-small"
                    :color="badgeColor('executed', v)"
                    :variant="badgeVariant('executed', v)"
                  >
                    Exec ({{ (v.executions || []).length }})
                  </v-chip>
                </div>
                <template #append>
                  <v-btn
                    v-if="v.version_id !== currentVersionId"
                    size="small"
                    variant="outlined"
                    :loading="restoringVersionId === v.version_id"
                    :disabled="!!restoringVersionId"
                    data-test="version-restore"
                    @click.stop="confirmRestore(v.version_id)"
                  >
                    Restore
                  </v-btn>
                </template>
              </v-list-item>
            </v-list>
          </v-col>
          <v-col cols="8" class="version-diff-pane">
            <div
              v-if="!selectedVersionId"
              class="pa-6 text-center text-medium-emphasis"
            >
              Select a version on the left to diff against the current version.
            </div>
            <div v-else-if="diffLoading" class="pa-6 text-center">
              <v-progress-circular indeterminate color="primary" />
            </div>
            <div v-else class="diff-frame">
              <div class="diff-header text-caption pa-2 d-flex align-center">
                <span>
                  Left:
                  <code>{{ selectedVersionId }}</code>
                  ({{ formatTimestamp(selectedVersionTimestamp) }})
                </span>
                <v-spacer />
                <span>Right: Current ({{ currentVersionId }})</span>
                <v-btn
                  icon="mdi-close"
                  size="small"
                  variant="text"
                  density="compact"
                  class="ml-2"
                  aria-label="Close diff"
                  data-test="version-diff-close"
                  @click="closeDiff"
                />
              </div>
              <div ref="differContainer" class="differ-container" />
            </div>
          </v-col>
        </v-row>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import AceDiff from 'ace-diff'
import 'ace-diff/styles.css'
import 'ace-diff/styles-twilight.css'

export default {
  name: 'ScriptVersionHistoryDialog',
  props: {
    modelValue: { type: Boolean, default: false },
    filename: { type: String, required: true },
    currentVersionId: { type: String, default: null },
    currentBody: { type: String, default: '' },
    lockedForReview: { type: Boolean, default: false },
    currentReviewer: { type: String, default: null },
    currentReviewerNotes: { type: String, default: null },
  },
  emits: ['update:modelValue', 'restored'],
  data() {
    return {
      loading: false,
      loadError: null,
      versions: [],
      selectedVersionId: null,
      selectedVersionTimestamp: null,
      diffLoading: false,
      differ: null,
      restoringVersionId: null,
    }
  },
  watch: {
    modelValue: function (open) {
      if (open) {
        this.loadVersions()
      } else {
        this.teardownDiffer()
        this.selectedVersionId = null
      }
    },
  },
  beforeUnmount() {
    this.teardownDiffer()
  },
  methods: {
    formatTimestamp(ts) {
      if (!ts) return ''
      try {
        return new Date(ts).toLocaleString()
      } catch (_) {
        return String(ts)
      }
    },
    reviewedLabel(v) {
      if (!v.reviewed) return 'Reviewed'
      const decision = v.reviewed.decision || 'approved'
      return decision === 'changes_requested' ? 'Changes' : 'Reviewed'
    },
    badgeColor(kind, v) {
      if (kind === 'validated') {
        if (!v.validated) return undefined
        return v.validated.passed ? 'success' : 'error'
      }
      if (kind === 'reviewed') {
        if (!v.reviewed) return undefined
        const decision = v.reviewed.decision || 'approved'
        return decision === 'changes_requested' ? 'error' : 'success'
      }
      if (kind === 'executed') {
        return (v.executions || []).length > 0 ? 'info' : undefined
      }
      return undefined
    },
    badgeVariant(kind, v) {
      let filled = false
      if (kind === 'validated') filled = !!v.validated
      else if (kind === 'reviewed') filled = !!v.reviewed
      else if (kind === 'executed') filled = (v.executions || []).length > 0
      return filled ? 'flat' : 'outlined'
    },
    async loadVersions() {
      this.loading = true
      this.loadError = null
      try {
        const response = await Api.get(
          `/script-api/scripts/${this.filename}/versions`,
        )
        this.versions = response.data?.versions || []
      } catch ({ response }) {
        this.loadError =
          response?.data?.message || response?.statusText || 'unknown'
      } finally {
        this.loading = false
      }
    },
    closeDiff() {
      this.selectedVersionId = null
      this.selectedVersionTimestamp = null
      this.teardownDiffer()
    },
    async selectVersion(versionId) {
      // Re-clicking the active row closes the diff — gives the user a way
      // back to the list overview without leaving the dialog.
      if (versionId === this.selectedVersionId) {
        this.closeDiff()
        return
      }
      if (versionId === this.currentVersionId) {
        // Selecting current = no meaningful diff. Show no diff.
        this.closeDiff()
        return
      }
      this.selectedVersionId = versionId
      const v = this.versions.find((x) => x.version_id === versionId)
      this.selectedVersionTimestamp = v?.last_modified || v?.saved_at
      this.diffLoading = true
      this.teardownDiffer()
      try {
        const response = await Api.get(
          `/script-api/scripts/${this.filename}/version`,
          { params: { version_id: versionId } },
        )
        const oldBody =
          typeof response.data === 'string'
            ? response.data
            : String(response.data ?? '')
        // Wait for the next tick so the differ container is in the DOM
        await this.$nextTick()
        this.diffLoading = false
        await this.$nextTick()
        if (this.$refs.differContainer) {
          this.differ = new AceDiff({
            element: this.$refs.differContainer,
            theme: 'ace/theme/twilight',
            left: {
              content: oldBody,
              editable: false,
              copyLinkEnabled: false,
            },
            right: {
              content: this.currentBody,
              editable: false,
              copyLinkEnabled: false,
            },
          })
        }
      } catch ({ response }) {
        this.diffLoading = false
        this.$notify.caution({
          title: 'Failed to load version',
          body: response?.data?.message || response?.statusText || 'unknown',
        })
      }
    },
    teardownDiffer() {
      if (this.differ) {
        try {
          this.differ.destroy()
        } catch (_) {
          // ace-diff doesn't always expose destroy on older versions
        }
        this.differ = null
      }
    },
    async confirmRestore(versionId) {
      // If the current version is reviewed-and-approved, restoring will
      // taint just like saving over a reviewed version.
      const proceed = this.lockedForReview
        ? await this.askTaintConfirm(versionId)
        : true
      if (!proceed) return
      await this.doRestore(versionId, this.lockedForReview)
    },
    askTaintConfirm(versionId) {
      const reviewer = this.currentReviewer || 'someone'
      const notes = this.currentReviewerNotes
        ? `\n\nReview notes: "${this.currentReviewerNotes}"`
        : ''
      return this.$dialog
        .confirm(
          `Restoring version ${versionId} will replace the current version, which was approved by ${reviewer}.${notes}\n\nProceed? The new version will be marked tainted.`,
          { okText: 'Restore Anyway', cancelText: 'Cancel' },
        )
        .then(() => true)
        .catch(() => false)
    },
    async doRestore(versionId, forceTaint) {
      this.restoringVersionId = versionId
      try {
        const url = forceTaint
          ? `/script-api/scripts/${this.filename}/restore?force_taint=true`
          : `/script-api/scripts/${this.filename}/restore`
        const response = await Api.post(url, {
          data: { version_id: versionId },
        })
        this.$notify.normal({
          title: 'Restored',
          body: `New version ${response.data?.version_id} created from ${versionId}.`,
        })
        this.$emit('restored', response.data?.version_id)
        this.$emit('update:modelValue', false)
      } catch ({ response }) {
        if (
          response?.status === 409 &&
          response?.data?.status === 'locked_for_review' &&
          !forceTaint
        ) {
          // Race: lock state changed between dialog open and restore click.
          const ok = await this.askTaintConfirm(versionId)
          if (ok) {
            await this.doRestore(versionId, true)
          }
        } else {
          this.$notify.caution({
            title: 'Restore Failed',
            body: response?.data?.message || `HTTP ${response?.status}`,
          })
        }
      } finally {
        this.restoringVersionId = null
      }
    },
  },
}
</script>

<style scoped>
.version-list-pane {
  border-right: 1px solid var(--v-theme-outline);
}
/* Pin the diff frame to fill the column. ace-diff creates ace editors
   that don't respect a flex-grow chain; without absolute positioning they
   expand to fit content and overflow the entire dialog (hiding the title
   bar and version list). */
.version-diff-pane {
  position: relative;
}
.diff-frame {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
}
.diff-header {
  flex-shrink: 0;
}
.differ-container {
  flex: 1 1 auto;
  width: 100%;
  min-height: 0;
}
.version-mini-badges {
  margin-top: 4px;
}
</style>
