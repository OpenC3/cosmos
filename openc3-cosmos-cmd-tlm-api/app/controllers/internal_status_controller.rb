# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/info_model'
require 'openc3/models/ping_model'

# InternalStatusController is designed to check the status of OpenC3. Status will
# check that Redis is up but that does not equal that everything is
# working just that OpenC3 can talk to Redis.
class InternalStatusController < ApplicationController
  def status
    begin
      render json: { status: OpenC3::PingModel.get() }
    rescue => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 500
    end
  end
end
