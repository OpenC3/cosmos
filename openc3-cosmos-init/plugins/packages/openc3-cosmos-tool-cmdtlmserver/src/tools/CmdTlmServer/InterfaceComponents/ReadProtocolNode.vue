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
  <div class="read-protocol-node">
    <v-icon color="#06b6d4" size="small">mdi-arrow-left-bold</v-icon>
    <div class="protocol-label">{{ data.label }}</div>
  </div>
</template>

<script>
export default {
  name: 'ReadProtocolNode',
  props: {
    data: {
      type: Object,
      required: true,
    },
  },
}
</script>

<style scoped>
.read-protocol-node {
  background: #ecfeff;
  border: 2px solid #06b6d4;
  border-radius: 4px;
  padding: 4px 6px;
  text-align: center;
  font-size: 10px;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
  position: absolute;
  z-index: 10;
  display: flex;
  align-items: center;
  justify-content: center;
  visibility: visible !important;
  cursor: pointer;
}

.protocol-label {
  font-weight: 500;
  font-size: 10px;
  margin: 2px 0;
  color: #374151;
}
</style>