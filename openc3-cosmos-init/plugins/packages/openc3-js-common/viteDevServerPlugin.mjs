/*
# Copyright 2024, OpenC3, Inc.
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
*/

import { spawn } from 'child_process'

let devServerPid
export const devServerPlugin = ({ mode }) => ({
  /* Hacky workaround since I can't get the vite dev server working correctly in our project.
   * The `vite` command is serving files from `outDir`, but somehow it doesn't refresh when those files are changed.
   * This simple plugin just listens for a couple vite hooks and spawns a new instance of vite to serve the new files.
   */
  name: 'dev-reload',
  buildEnd() {
    // Called after Rollup finishes, but before files are written
    if (mode !== 'dev-server') {
      return
    }
    devServerPid && process.kill(devServerPid)
    devServerPid = null
  },
  closeBundle() {
    // Called after build output files are written
    if (mode !== 'dev-server') {
      return
    }
    const v = spawn('vite')
    devServerPid = v.pid
  },
})
