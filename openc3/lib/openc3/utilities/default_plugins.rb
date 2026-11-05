# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'yaml'

module OpenC3
  # The plugins that ship with COSMOS. The list lives in
  # data/config/default_plugins.yaml and is shared with the Admin Plugins tab
  # and the script API via the 'default' flag from GET /openc3-api/plugins/all
  module DefaultPlugins
    # Short names, i.e. without the version or the __ suffix
    NAMES = YAML.safe_load_file(
      File.expand_path('../../../data/config/default_plugins.yaml', __dir__)
    ).freeze

    # True if the plugin (e.g. "openc3-cosmos-tool-admin-6.0.0.gem__20260101000000")
    # is one that ships with COSMOS
    def self.default?(plugin_name)
      # Strip the __ suffix and the trailing -version.gem to get the short name
      NAMES.include?(plugin_name.split('__')[0].split('-')[0..-2].join('-'))
    end
  end
end
