<!--
# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div class="target-node">
    <!-- Input handles on the left -->
    <Handle
      id="target__cmd"
      type="target"
      position="left"
      :style="{
        top: '114px',
      }"
    />
    <Handle
      id="target__tlm"
      type="target"
      position="left"
      :style="{
        top: '164px',
      }"
    />
    <div style="position:absolute;top:104px;left:8px;color:black;">CMD</div>
    <div style="position:absolute;top:154px;left:8px;color:black;">TLM</div>
    <v-icon color="#10b981">mdi-target</v-icon>
    <div class="node-label">{{ data.label }}</div>
    <div class="node-label">Target</div>
  </div>
</template>

<script>
import { Handle } from '@vue-flow/core'

export default {
  name: 'TargetNode',
  components: {
    Handle,
  },
  props: {
    data: {
      type: Object,
      required: true,
    },
  },
}
</script>

<style scoped>
.target-node {
  background: #ffffff;
  border: 2px solid #10b981;
  border-radius: 8px;
  padding: 10px;
  text-align: center;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  height:200px;
  width:200px;
}

.node-label {
  font-weight: 500;
  margin: 4px 0;
  font-size: 14px;
  color: #1f2937;
}
</style>
