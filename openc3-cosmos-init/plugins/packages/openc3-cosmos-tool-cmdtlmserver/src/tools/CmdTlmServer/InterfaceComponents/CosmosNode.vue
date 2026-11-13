<!--
# Copyright 2025 OpenC3, Inc.
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
  <div class="cosmos-node" :class="`flow-node--${health.state}`">
    <!-- Input handles on the left -->
    <Handle
      id="cosmos__cmd"
      type="target"
      position="right"
      style="top: 114px"
    />
    <Handle
      id="cosmos__tlm"
      type="target"
      position="right"
      style="top: 164px"
    />
    <div style="position: absolute; top: 104px; right: 8px; color: black">
      CMD
    </div>
    <div style="position: absolute; top: 154px; right: 8px; color: black">
      TLM
    </div>
    <v-icon color="#10b981">mdi-rocket-launch</v-icon>
    <div class="node-label">{{ data.label }}</div>
    <div class="node-label">Processing</div>
    <FlowHealthIndicator
      :health="health"
      :name="data.label"
      @details="$emit('details')"
    />
  </div>
</template>

<script>
import { Handle } from '@vue-flow/core'
import FlowHealthIndicator from './FlowHealthIndicator.vue'
import { flowHealth } from './flowMetrics'

export default {
  name: 'CosmosNode',
  components: {
    Handle,
    FlowHealthIndicator,
  },
  props: {
    health: { type: Object, default: () => flowHealth() },
    data: {
      type: Object,
      required: true,
    },
  },
  emits: ['details'],
}
</script>

<style scoped>
.cosmos-node {
  position: relative;
  cursor: pointer;
  background: #ffffff;
  border: 2px solid #10b981;
  border-radius: 8px;
  padding: 10px;
  text-align: center;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  height: 212px;
  width: 200px;
}

.node-label {
  font-weight: 500;
  margin: 4px 0;
  font-size: 14px;
  color: #1f2937;
}
</style>
