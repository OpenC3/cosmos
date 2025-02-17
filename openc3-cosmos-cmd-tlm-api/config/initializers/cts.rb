# encoding: ascii-8bit

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

require 'openc3/api/authorized_api'
require 'openc3/io/json_drb'
require 'openc3/models/setting_model'
require 'openc3/version'

module OpenC3
  class Cts
    # This sets a global flag $openc3_authorize = true
    # which is used by authorization.rb to enable the
    # role and permission checks. This is because the Cts
    # is an internal microservice inside the trust zone.
    include AuthorizedApi

    attr_accessor :json_drb

    @@instance = nil

    def initialize
      @json_drb = JsonDRb.new
      @json_drb.method_whitelist = Api::WHITELIST.to_set
      @json_drb.object = self
    end

    def self.instance
      @@instance ||= new()
    end
  end
end

# Create the single Cts instance which instantiates the JsonDRb
# This is used by openc3-cosmos-cmd-tlm-api/app/controllers/api_controller.rb
# to process API requests
OpenC3::Cts.instance

# Accessing Redis early can break specs
unless ENV['OPENC3_NO_STORE']
  # Set the displayed OpenC3 version
  if defined? OPENC3_ENTERPRISE_VERSION
    OpenC3::SettingModel.set({ name: 'version', data: OPENC3_ENTERPRISE_VERSION }, scope: nil)
  else
    OpenC3::SettingModel.set({ name: 'version', data: OPENC3_VERSION }, scope: nil)
  end
end
