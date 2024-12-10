<!--
# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div class="value-widget-container">
    <template>
      <v-text-field
        solo
        density="compact"
        readonly
        single-line
        hide-no-data
        hide-details
        :value="_value"
        :class="valueClass"
        :style="computedStyle"
        data-test="value"
      />
    </template>
  </div>
</template>

<script>
import { VWidget } from '@openc3/vue-common/widgets'

export default {
  mixins: [VWidget],
}
</script>

<style lang="scss" scoped>
.value-widget-container {
  min-height: 100px;
}
.value-widget-container :deep(input) {
  max-height: none !important;
  line-height: 70px !important;
  font-size: 60px !important;
}
</style>
