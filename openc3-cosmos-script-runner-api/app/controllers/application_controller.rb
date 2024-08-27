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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/authorization'

class ApplicationController < ActionController::API
  include OpenC3::Authorization

  private

  def user_full_name()
    # For user_info see openc3/utilities/authorization and
    # openc3_enterprise/utilities/authorization
    user = user_info(request.headers['HTTP_AUTHORIZATION'])
    name = user['name']
    # Open Source name (EE has the actual name)
    name ||= 'Anonymous'
    return name
  end

  def username()
    # For user_info see openc3/utilities/authorization and
    # openc3_enterprise/utilities/authorization
    user = user_info(request.headers['HTTP_AUTHORIZATION'])
    username = user['username']
    # Open Source username (EE has the actual username)
    username ||= 'anonymous'
    return username
  end

  # Authorize and rescue the possible exceptions
  # @return [Boolean] true if authorize successful
  def authorization(permission, target_name: nil)
    begin
      authorize(
        permission: permission,
        target_name: target_name,
        manual: request.headers['HTTP_MANUAL'],
        scope: params[:scope],
        token: request.headers['HTTP_AUTHORIZATION'],
      )
    rescue OpenC3::AuthError => e
      render(json: { status: 'error', message: e.message }, status: 401) and
        return false
    rescue OpenC3::ForbiddenError => e
      render(json: { status: 'error', message: e.message }, status: 403) and
        return false
    end
    true
  end
end
