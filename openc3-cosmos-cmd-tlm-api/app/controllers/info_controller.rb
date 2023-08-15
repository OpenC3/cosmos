# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

begin
  require 'openc3/version'
  require 'openc3-enterprise/controllers/info_controller'
rescue LoadError
  class InfoController < ApplicationController
    def info
      render :json => { :version => OPENC3_VERSION, :license => 'AGPLv3', :enterprise => false }, :status => 200
    end
  end
end
