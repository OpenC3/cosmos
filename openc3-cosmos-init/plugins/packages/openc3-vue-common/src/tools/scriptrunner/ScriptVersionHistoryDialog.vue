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
          <v-col
            class="version-list-pane overflow-auto"
            style="flex: 0 0 25%; max-width: 25%"
          >
            <div
              v-if="versions.length === 0"
              class="pa-6 text-center text-medium-emphasis"
              data-test="version-list-empty"
            >
              No version history available for this script.
            </div>
            <v-list v-else density="compact" data-test="version-list">
              <v-list-item
                v-for="(v, idx) in versions"
                :key="v.version_id"
                :active="selectedVersionId === v.version_id"
                @click="selectVersion(v.version_id)"
              >
                <template #prepend>
                  <v-tooltip :open-delay="600" location="top">
                    <template #activator="{ props: tt }">
                      <v-icon
                        v-bind="tt"
                        :color="
                          v.version_id === compareVersionId
                            ? 'primary'
                            : undefined
                        "
                        style="cursor: pointer"
                        data-test="version-compare"
                        @click.stop="setCompare(v.version_id)"
                      >
                        {{
                          v.version_id === compareVersionId
                            ? 'mdi-bookmark'
                            : 'mdi-bookmark-outline'
                        }}
                      </v-icon>
                    </template>
                    <span>Diff to this version</span>
                  </v-tooltip>
                </template>
                <v-list-item-title class="text-body-2">
                  <span>Version {{ versions.length - idx }}</span>
                  <span v-if="idx === 0" class="ml-2">
                    <v-chip size="x-small" color="primary" variant="tonal">
                      Current
                    </v-chip>
                  </span>
                </v-list-item-title>
                <v-list-item-subtitle>
                  {{ formatTimestamp(v.last_modified) }}
                </v-list-item-subtitle>
                <template #append>
                  <v-btn
                    v-if="idx !== 0"
                    size="small"
                    variant="outlined"
                    :loading="restoringVersionId === v.version_id"
                    :disabled="!!restoringVersionId"
                    data-test="version-restore"
                    @click.stop="doRestore(v.version_id)"
                  >
                    Restore
                  </v-btn>
                </template>
              </v-list-item>
              <v-list-item>
                <span>Restoring a version creates a new version.</span>
              </v-list-item>
            </v-list>
          </v-col>
          <v-col
            class="version-diff-pane"
            style="flex: 0 0 75%; max-width: 75%"
          >
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
              <div class="diff-header d-flex align-stretch">
                <div class="diff-header-half diff-header-left">
                  <span class="diff-header-label">Left</span>
                  <span class="diff-header-value">{{ leftLabel }}</span>
                </div>
                <div class="diff-header-half diff-header-right">
                  <span class="diff-header-label">Right</span>
                  <span class="diff-header-value">{{ rightLabel }}</span>
                </div>
                <v-btn
                  icon="mdi-close"
                  size="small"
                  variant="text"
                  density="compact"
                  class="ml-2 align-self-center"
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
// Register the language modes so ace-diff editors get syntax highlighting.
// Importing these from ace-builds wires them into the global ace registry.
import 'ace-builds/src-noconflict/mode-ruby'
import 'ace-builds/src-noconflict/mode-python'
import 'ace-builds/src-noconflict/mode-javascript'
import 'ace-builds/src-noconflict/mode-text'

export default {
  name: 'ScriptVersionHistoryDialog',
  props: {
    modelValue: { type: Boolean, default: false },
    filename: { type: String, required: true },
    currentBody: { type: String, default: '' },
  },
  emits: ['update:modelValue', 'restored'],
  data() {
    return {
      loading: false,
      loadError: null,
      versions: [],
      selectedVersionId: null,
      selectedVersionTimestamp: null,
      compareVersionId: null,
      diffLoading: false,
      differ: null,
      restoringVersionId: null,
    }
  },
  computed: {
    aceMode() {
      const ext = (this.filename || '').toLowerCase().split('.').pop()
      if (ext === 'py') return 'ace/mode/python'
      if (ext === 'rb' || ext === 'rake' || ext === 'gemspec')
        return 'ace/mode/ruby'
      if (ext === 'js') return 'ace/mode/javascript'
      return 'ace/mode/text'
    },
    versionLabel() {
      // version_id → "Version N" using the list ordering (newest first).
      return (versionId) => {
        const idx = this.versions.findIndex((x) => x.version_id === versionId)
        if (idx < 0) return versionId
        return `Version ${this.versions.length - idx}`
      }
    },
    leftLabel() {
      if (!this.selectedVersionId) return ''
      const ts = this.formatTimestamp(this.selectedVersionTimestamp)
      return `${this.versionLabel(this.selectedVersionId)} (${ts})`
    },
    rightLabel() {
      if (!this.compareVersionId) return 'Current'
      const v = this.versions.find(
        (x) => x.version_id === this.compareVersionId,
      )
      const ts = v ? this.formatTimestamp(v.last_modified) : ''
      const label = this.versionLabel(this.compareVersionId)
      // The newest version is what the editor shows as "Current".
      const suffix =
        this.compareVersionId === this.versions[0]?.version_id
          ? ' — Current'
          : ''
      return `${label}${suffix} (${ts})`
    },
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
  mounted() {
    // Parent uses v-if to remount on each open, so modelValue is already true
    // here and the watcher won't fire — load versions on initial mount.
    if (this.modelValue) {
      this.loadVersions()
    }
  },
  beforeUnmount() {
    this.teardownDiffer()
  },
  methods: {
    formatTimestamp(ts) {
      if (!ts) return ''
      const formatted = new Date(ts).toLocaleString()
      return formatted === 'Invalid Date' ? String(ts) : formatted
    },
    async loadVersions() {
      this.loading = true
      this.loadError = null
      try {
        const response = await Api.get(
          `/script-api/scripts/${this.filename}/versions`,
        )
        this.versions = response.data?.versions || []
        // Default the diff target (right side) to the newest version, which
        // is what the editor is currently displaying.
        this.compareVersionId = this.versions[0]?.version_id || null
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
      // Re-clicking the active row closes the diff.
      if (versionId === this.selectedVersionId) {
        this.closeDiff()
        return
      }
      // Selecting the same version as the diff target = no meaningful diff.
      if (versionId === this.compareVersionId) {
        this.closeDiff()
        return
      }
      const idx = this.versions.findIndex((x) => x.version_id === versionId)
      this.selectedVersionId = versionId
      this.selectedVersionTimestamp = this.versions[idx]?.last_modified
      await this.renderDiff()
    },
    async setCompare(versionId) {
      this.compareVersionId = versionId
      // Reset the left side if the user just made the diff trivial.
      if (this.selectedVersionId === versionId) {
        this.closeDiff()
        return
      }
      if (this.selectedVersionId) {
        await this.renderDiff()
      }
    },
    async fetchVersionBody(versionId) {
      // Latest version body lives in the parent editor — avoid a round-trip
      // and use it directly so the right side stays in sync with unsaved
      // edits if the user is mid-edit.
      if (versionId === this.versions[0]?.version_id) {
        return this.currentBody
      }
      const response = await Api.get(
        `/script-api/scripts/${this.filename}/version`,
        { params: { version_id: versionId } },
      )
      return typeof response.data === 'string'
        ? response.data
        : String(response.data ?? '')
    },
    async renderDiff() {
      if (!this.selectedVersionId || !this.compareVersionId) return
      this.diffLoading = true
      this.teardownDiffer()
      try {
        const [leftBody, rightBody] = await Promise.all([
          this.fetchVersionBody(this.selectedVersionId),
          this.fetchVersionBody(this.compareVersionId),
        ])
        await this.$nextTick()
        this.diffLoading = false
        await this.$nextTick()
        if (this.$refs.differContainer) {
          const mode = this.aceMode
          this.differ = new AceDiff({
            element: this.$refs.differContainer,
            mode,
            theme: 'ace/theme/twilight',
            left: {
              content: leftBody,
              mode,
              editable: false,
              copyLinkEnabled: false,
            },
            right: {
              content: rightBody,
              mode,
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
        // ace-diff doesn't always expose destroy on older versions
        if (typeof this.differ.destroy === 'function') {
          this.differ.destroy()
        }
        this.differ = null
      }
    },
    async doRestore(versionId) {
      this.restoringVersionId = versionId
      try {
        const response = await Api.post(
          `/script-api/scripts/${this.filename}/restore`,
          { data: { version_id: versionId } },
        )
        this.$notify.normal({
          title: 'Restored',
          body: `New version ${response.data?.version_id} created from ${versionId}.`,
        })
        this.$emit('restored', response.data?.version_id)
        this.$emit('update:modelValue', false)
      } catch ({ response }) {
        this.$notify.caution({
          title: 'Restore Failed',
          body: response?.data?.message || `HTTP ${response?.status}`,
        })
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
  background-color: rgba(255, 255, 255, 0.04);
  border-bottom: 1px solid var(--v-theme-outline);
}
/* Two halves match ace-diff's 50/50 internal split so each label sits over
   the editor it describes. */
.diff-header-half {
  flex: 1 1 50%;
  min-width: 0;
  padding: 6px 12px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.diff-header-left {
  border-right: 1px solid var(--v-theme-outline);
}
.diff-header-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  opacity: 0.6;
}
.diff-header-value {
  font-size: 13px;
  font-weight: 500;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.differ-container {
  flex: 1 1 auto;
  width: 100%;
  min-height: 0;
  /* ace-diff positions its editors absolute; without an explicit positioning
     context they anchor to the .diff-frame and overlap the header above. */
  position: relative;
  overflow: hidden;
}
</style>
