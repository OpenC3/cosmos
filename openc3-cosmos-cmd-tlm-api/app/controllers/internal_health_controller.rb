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

# InternalHealthController is designed to check the health of OpenC3. Health
# will return the Redis info method and can be expanded on. From here the
# user can see how Redis is and determine health.
class InternalHealthController < ApplicationController
  def health
    return unless authorization('system')
    begin
      render json: { redis: OpenC3::InfoModel.get() }
    rescue => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 500
    end
  end
end
