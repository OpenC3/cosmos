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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/authorization'

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include OpenC3::Authorization

    identified_by :uuid
    identified_by :scope

    def connect
      authorization('system')
      self.uuid = SecureRandom.uuid
      self.scope = request.headers['HTTP_X_OPENC3_SCOPE'] || request.query_parameters[:scope]
    end

    def authorization(permission)
      begin
        authorize(
          permission: permission,
          scope: request.headers['HTTP_X_OPENC3_SCOPE'] || request.query_parameters[:scope],
          token: request.headers['HTTP_AUTHORIZATION'] || request.query_parameters[:authorization],
        )
      rescue OpenC3::AuthError, OpenC3::ForbiddenError
        reject_unauthorized_connection()
      end
      true
    end
  end
end
