/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license 
# if purchased from OpenC3, Inc.
*/

const TabsList = [
  {
    displayName: 'Plugins',
    path: 'plugins',
    component: () => import('./PluginsTab'),
  },
  {
    displayName: 'Targets',
    path: 'targets',
    component: () => import('./TargetsTab'),
  },
  {
    displayName: 'Interfaces',
    path: 'interfaces',
    component: () => import('./InterfacesTab'),
  },
  {
    displayName: 'Routers',
    path: 'routers',
    component: () => import('./RoutersTab'),
  },
  {
    displayName: 'Microservices',
    path: 'microservices',
    component: () => import('./MicroservicesTab'),
  },
  {
    displayName: 'Gems',
    path: 'gems',
    component: () => import('./GemsTab'),
  },
  {
    displayName: 'Tools',
    path: 'tools',
    component: () => import('./ToolsTab'),
  },
  {
    displayName: 'Redis',
    path: 'redis',
    component: () => import('./RedisTab'),
  },
  {
    displayName: 'Settings',
    path: 'settings',
    component: () => import('./SettingsTab'),
  },
]

export { TabsList }
