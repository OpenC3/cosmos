<!--
# Copyright 2022 OpenC3, Inc.
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
  <graph
    :ref="'graph' + id"
    :id="id"
    :state="state"
    :selected-graph-id="id"
    :startTime="startTime"
    :seconds-graphed="secondsGraphed"
    :points-saved="pointsSaved"
    :points-graphed="pointsGraphed"
    :initial-items="items"
    :height="size.height"
    :width="size.width"
    :style="computedStyle"
    sparkline
  />
</template>

<script>
import GraphWidget from './GraphWidget'
import { Graph } from '@/components'

export default {
  components: {
    Graph,
  },
  mixins: [GraphWidget],
  data: function () {
    return {
      // 5min of data in the sparkline
      secondsGraphed: 300,
      pointsSaved: 300,
      pointsGraphed: 300,
      // Reduce the size
      size: {
        height: 30,
        width: 130,
      },
    }
  },
}
</script>
