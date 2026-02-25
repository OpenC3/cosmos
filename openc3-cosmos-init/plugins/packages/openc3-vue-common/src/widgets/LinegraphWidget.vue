<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <graph
    :id="id"
    :ref="'graph' + id"
    :state="state"
    :selected-graph-id="id"
    :start-time="startTime"
    :seconds-graphed="secondsGraphed"
    :points-saved="pointsSaved"
    :points-graphed="pointsGraphed"
    :initial-items="items"
    :height="size.height"
    :width="size.width"
    :style="computedStyle"
    :time-zone="screenTimeZone"
    hide-toolbar
    hide-overview
    @pause="() => (state = 'pause')"
    @start="() => (state = 'start')"
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
}
</script>
