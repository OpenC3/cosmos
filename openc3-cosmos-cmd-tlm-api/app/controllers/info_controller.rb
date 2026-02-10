# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

begin
  require 'openc3/version'
  require 'openc3-enterprise/controllers/info_controller'
rescue LoadError
  class InfoController < ApplicationController
    def info
      render json: { version: OPENC3_VERSION, license: 'OpenC3', enterprise: false }
    end
  end
end
