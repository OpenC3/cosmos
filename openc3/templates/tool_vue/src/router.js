/*
# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import Vue from 'vue'
import Router from 'vue-router'

Vue.use(Router)

export default new Router({
  mode: 'history',
  base: process.env.BASE_URL,
  routes: [
    {
      path: '/',
      name: '<%= tool_name %>',
      component: () => import('./tools/<%= tool_name %>/<%= tool_name %>.vue'),
    },
    {
      path: '*',
      name: 'NotFound',
      component: () => import('@openc3/tool-common/src/components/NotFound'),
    },
  ],
})
