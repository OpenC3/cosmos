/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { Api } from '@openc3/js-common/services'

// Locating a target file, i.e. 'INST/cmd_tlm/inst_cmds.txt'. A file the user
// has modified lives under targets_modified and the installed one under
// targets. Rather than requesting from targets_modified and treating the 404 as
// the answer, ask the target which of its files are modified: one request per
// target instead of one per file, and no failed requests. The browser logs
// every 404 to the console no matter how the code handles it, so a screen full
// of images or files produced a wall of red for a case that isn't an error.
export default {
  data() {
    return {
      // Target name to a promise of the Set of that target's modified files.
      // Per component instance rather than module level so a widget picks up
      // files modified since some other screen last looked.
      modifiedTargetFiles: {},
    }
  },
  methods: {
    // Nothing tells us when a file becomes modified, so anything that refetches
    // on the user's behalf has to drop what we learned first. Otherwise a file
    // modified after the widget mounted keeps resolving to the installed copy
    // and a refresh returns the same answer forever.
    clearTargetFileCache() {
      this.modifiedTargetFiles = {}
    },
    // 'targets_modified' or 'targets', whichever holds this file
    async targetFileRoot(filePath) {
      const targetName = filePath.split('/')[0]
      if (!this.modifiedTargetFiles[targetName]) {
        this.modifiedTargetFiles[targetName] = Api.get(
          `/openc3-api/targets/${encodeURIComponent(targetName)}/modified_files`,
          { headers: { 'Ignore-Errors': '404,500' } },
        )
          // modified_files reports target relative paths, the same shape we
          // were given. If we can't tell, assume the installed file.
          .then((response) => new Set(response.data))
          .catch(() => new Set())
      }
      const modified = await this.modifiedTargetFiles[targetName]
      return modified.has(filePath) ? 'targets_modified' : 'targets'
    },
    // The contents of a target file as a string
    async fetchTargetFile(filePath) {
      const scope = window.openc3Scope || 'DEFAULT'
      const root = await this.targetFileRoot(filePath)
      const objectPath = `${scope}/${root}/${filePath}`
      const response = await Api.get(
        `/openc3-api/storage/download_file/${encodeURIComponent(objectPath)}`,
        { params: { bucket: 'OPENC3_CONFIG_BUCKET' } },
      )
      if (response?.data?.contents) {
        return atob(response.data.contents)
      }
      throw new Error('File not found')
    },
  },
}
