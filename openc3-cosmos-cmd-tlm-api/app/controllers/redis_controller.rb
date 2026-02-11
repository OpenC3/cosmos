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

class RedisController < ApplicationController
  DISALLOWED_COMMANDS = [
    'AUTH' # Because changing the Redis ACL user will break cmd-tlm-api
  ]

  def execute_raw
    return unless authorization('admin')

    args = request.body.read.split(' ').compact

    # Check that we allow this command
    command = args[0].upcase
    if DISALLOWED_COMMANDS.include? command
      render json: { status: 'error', message: "The #{command} command is not allowed." }, status: 422
      return
    end

    if params[:ephemeral]
      result = OpenC3::EphemeralStore.method_missing(command, args[1..-1])
    else
      result = OpenC3::Store.method_missing(command, args[1..-1])
    end
    OpenC3::Logger.info("Redis command executed: #{args} - with result #{result}", user: username())
    render json: { :result => result }, status: 201
  end
end
