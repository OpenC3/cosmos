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
  <div class="router-node" :style="routerStyle">
    <v-icon color="#ba1de1">mdi-call-split</v-icon>
    <div class="node-label">{{ data.label }}</div>
    <div class="node-label">Router</div>
    <!-- Output handles on the right -->
    <!-- Input handles on the left -->
    <Handle
      id="router__cmd__input"
      type="target"
      position="left"
      :style="{
        top: '112px',
      }"
    />
    <Handle
      id="router__tlm__input"
      type="target"
      position="left"
      :style="{
        top: '162px',
      }"
    />
    <Handle
      id="router__cmd__output"
      type="source"
      position="right"
      :style="{
        top: '112px',
      }"
    />
    <Handle
      id="router__tlm__output"
      type="source"
      position="right"
      :style="{
        top: '162px',
      }"
    />
    <div style="position:absolute;top:102px;left:8px;color:black;">CMD</div>
    <div style="position:absolute;top:152px;left:8px;color:black;">TLM</div>
    <div style="position:absolute;top:102px;right:8px;color:black;">CMD</div>
    <div style="position:absolute;top:152px;right:8px;color:black;">TLM</div>
  </div>
</template>

<script>
import { Handle } from '@vue-flow/core'

export default {
  name: 'RouterNode',
  components: {
    Handle,
  },
  props: {
    data: {
      type: Object,
      required: true,
    },
  },
  computed: {
    routerStyle() {
      return { width: `${this.data.width}px`, height: `${this.data.height}px` }
    },
  },
  data() {
    return {
    }
  },
}
</script>

<style scoped>
.router-node {
  position: relative;
  background: #ffffff;
  border: 2px solid #ba1de1;
  border-radius: 8px;
  text-align: center;
  padding: 10px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  cursor: pointer;
}

.node-label {
  font-weight: 500;
  margin: 4px 0;
  font-size: 14px;
  color: #1f2937;
}
</style>
