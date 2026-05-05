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
  <div class="lifecycle-badges d-flex align-center">
    <!-- Validated badge -->
    <v-tooltip location="bottom">
      <template #activator="{ props }">
        <v-chip
          v-bind="props"
          size="small"
          :color="validatedColor"
          :variant="validatedVariant"
          :prepend-icon="validatedIcon"
          class="mr-2"
          data-test="lifecycle-badge-validated"
        >
          Validated
        </v-chip>
      </template>
      <span class="badge-tooltip">
        <strong>Validated</strong><br />
        <template v-if="validated">
          <template v-if="validated.passed">
            Syntax + mnemonic check passed
          </template>
          <template v-else>
            Failed:
            <ul>
              <li v-for="(err, idx) in validated.errors || []" :key="idx">
                {{ err }}
              </li>
            </ul>
          </template>
        </template>
        <template v-else> Not yet validated </template>
      </span>
    </v-tooltip>

    <!-- Reviewed badge -->
    <v-tooltip location="bottom">
      <template #activator="{ props }">
        <v-chip
          v-bind="props"
          size="small"
          :color="reviewedColor"
          :variant="reviewedVariant"
          :prepend-icon="reviewedIcon"
          class="mr-2"
          data-test="lifecycle-badge-reviewed"
        >
          {{ reviewedLabel }}
        </v-chip>
      </template>
      <span class="badge-tooltip">
        <strong>{{ reviewedTitle }}</strong
        ><br />
        <template v-if="reviewed">
          By <strong>{{ reviewed.by }}</strong> at {{ reviewed.at }}
          <template v-if="reviewed.notes">
            <br />Notes: {{ reviewed.notes }}
          </template>
        </template>
        <template v-else-if="hadPriorApprovedReview">
          A previous version of this script was approved, but the current
          version has not yet been signed off.
        </template>
        <template v-else> Not yet signed off </template>
      </span>
    </v-tooltip>

    <!-- Executed badge -->
    <v-tooltip location="bottom">
      <template #activator="{ props }">
        <v-chip
          v-bind="props"
          size="small"
          :color="executedColor"
          :variant="executedVariant"
          :prepend-icon="executedIcon"
          class="mr-2"
          data-test="lifecycle-badge-executed"
        >
          Executed{{ executions.length > 1 ? ` (${executions.length})` : '' }}
        </v-chip>
      </template>
      <span class="badge-tooltip">
        <strong>Executed</strong><br />
        <template v-if="executions.length === 0">
          Never run from this version
        </template>
        <template v-else>
          {{ executions.length }} run<template v-if="executions.length !== 1"
            >s</template
          >
          recorded.<br />
          Latest: by <strong>{{ latestExecution.by }}</strong> at
          {{ latestExecution.at }}
          <template v-if="latestExecution.disconnect"> (disconnect)</template>
          <template v-if="latestExecution.running_script_id">
            <br />Script ID: {{ latestExecution.running_script_id }}
          </template>
          <template v-if="latestExecutionStatus">
            <br />Status: <strong>{{ latestExecutionStatus }}</strong>
          </template>
        </template>
      </span>
    </v-tooltip>

    <!-- Tainted indicator -->
    <v-tooltip v-if="tainted" location="bottom">
      <template #activator="{ props }">
        <v-chip
          v-bind="props"
          size="small"
          color="warning"
          variant="flat"
          prepend-icon="mdi-alert"
          class="mr-2"
          data-test="lifecycle-badge-tainted"
        >
          Tainted
        </v-chip>
      </template>
      <span class="badge-tooltip">
        <strong>Tainted</strong><br />
        Edited from a previously reviewed version (signed off by
        <strong>{{ taintedFromReviewedBy }}</strong
        >).
      </span>
    </v-tooltip>
  </div>
</template>

<script>
export default {
  name: 'ScriptLifecycleBadges',
  props: {
    lifecycle: {
      type: Object,
      default: null,
    },
    // True when an earlier (non-latest) version of this script was approved.
    // Drives the "dull green" rendering when the current version isn't yet
    // reviewed but the script has historical sign-offs.
    hadPriorApprovedReview: {
      type: Boolean,
      default: false,
    },
    // Optional ScriptStatusModel state for the most recent execution. The
    // parent fetches it on file load and mirrors live state changes from the
    // running-script WebSocket. Used to color the executed badge.
    latestExecutionStatus: {
      type: String,
      default: null,
    },
  },
  computed: {
    validated() {
      return this.lifecycle?.validated || null
    },
    reviewed() {
      return this.lifecycle?.reviewed || null
    },
    executions() {
      return this.lifecycle?.executions || []
    },
    latestExecution() {
      return this.executions[this.executions.length - 1] || {}
    },
    tainted() {
      return this.lifecycle?.tainted === true
    },
    taintedFromReviewedBy() {
      return this.lifecycle?.tainted_from_reviewed_by
    },
    // Empty (grey outline) when no data. Filled with color once the facet
    // acquires data; validation pass = success, fail = error.
    validatedColor() {
      if (!this.validated) return undefined
      return this.validated.passed ? 'success' : 'error'
    },
    validatedVariant() {
      return this.validated ? 'flat' : 'outlined'
    },
    validatedIcon() {
      if (!this.validated) return 'mdi-circle-outline'
      return this.validated.passed ? 'mdi-check-circle' : 'mdi-alert-circle'
    },
    reviewDecision() {
      // Treat a missing decision field as 'approved' for back-compat with
      // reviews recorded before the field existed.
      if (!this.reviewed) return null
      return this.reviewed.decision || 'approved'
    },
    reviewedLabel() {
      if (this.reviewDecision === 'changes_requested')
        return 'Changes Requested'
      return 'Reviewed'
    },
    reviewedTitle() {
      if (this.reviewDecision === 'changes_requested')
        return 'Changes Requested'
      if (this.reviewDecision === 'approved') return 'Reviewed (Approved)'
      if (this.hadPriorApprovedReview) return 'Reviewed (prior version)'
      return 'Reviewed'
    },
    // Color logic mirroring validated/executed:
    //   bright green (success/flat)   — current version approved
    //   red (error/flat)              — current version: changes requested
    //   dull green (success/tonal)    — a previous version was approved
    //   grey outline                  — never reviewed
    reviewedColor() {
      if (this.reviewDecision === 'approved') return 'success'
      if (this.reviewDecision === 'changes_requested') return 'error'
      if (this.hadPriorApprovedReview) return 'success'
      return undefined
    },
    reviewedVariant() {
      if (this.reviewDecision === 'approved') return 'flat'
      if (this.reviewDecision === 'changes_requested') return 'flat'
      if (this.hadPriorApprovedReview) return 'tonal'
      return 'outlined'
    },
    reviewedIcon() {
      if (this.reviewDecision === 'approved') return 'mdi-account-check'
      if (this.reviewDecision === 'changes_requested')
        return 'mdi-account-alert'
      if (this.hadPriorApprovedReview) return 'mdi-account-check-outline'
      return 'mdi-circle-outline'
    },
    // Bucket the wide ScriptStatusModel state vocabulary into UI categories:
    //   success   — completed cleanly
    //   warning   — completed but with errors
    //   error     — crashed, killed, errored, or stopped (abnormal end)
    //   running   — script is in flight (still executing)
    //   null      — outcome unknown (e.g. completed entry rotated out of Redis)
    executedStatusCategory() {
      const s = this.latestExecutionStatus
      if (!s) return null
      if (s === 'completed') return 'success'
      if (s === 'completed_errors') return 'warning'
      if (['crashed', 'killed', 'error', 'stopped'].includes(s)) return 'error'
      if (
        [
          'running',
          'paused',
          'waiting',
          'breakpoint',
          'init',
          'spawning',
        ].includes(s)
      )
        return 'running'
      return null
    },
    executedColor() {
      if (this.executions.length === 0) return undefined
      const cat = this.executedStatusCategory
      if (cat === 'success') return 'success'
      if (cat === 'warning') return 'warning'
      if (cat === 'error') return 'error'
      if (cat === 'running') return 'info'
      // Have executions but status is unknown — keep info as a soft signal
      // that something has run.
      return 'info'
    },
    executedVariant() {
      if (this.executions.length === 0) return 'outlined'
      // Use tonal while a run is still in flight to differentiate from
      // terminal states.
      if (this.executedStatusCategory === 'running') return 'tonal'
      return 'flat'
    },
    executedIcon() {
      if (this.executions.length === 0) return 'mdi-circle-outline'
      const cat = this.executedStatusCategory
      if (cat === 'success') return 'mdi-check-circle'
      if (cat === 'warning') return 'mdi-alert'
      if (cat === 'error') return 'mdi-close-circle'
      if (cat === 'running') return 'mdi-play-circle-outline'
      return 'mdi-play-circle'
    },
  },
}
</script>

<style scoped>
.lifecycle-badges {
  flex-shrink: 0;
}
.badge-tooltip {
  display: inline-block;
  max-width: 320px;
}
.badge-tooltip ul {
  margin-left: 1.2rem;
}
</style>
