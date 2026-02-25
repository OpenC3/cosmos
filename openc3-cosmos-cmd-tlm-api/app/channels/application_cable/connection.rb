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

require 'openc3/utilities/authorization'

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include OpenC3::Authorization

    identified_by :uuid
    identified_by :scope

    def connect
      authorization('system')
      self.uuid = SecureRandom.uuid
      self.scope = request.query_parameters[:scope]
    end

    def authorization(permission)
      begin
        authorize(
          permission: permission,
          scope: request.query_parameters[:scope],
          token: request.query_parameters[:authorization],
        )
      rescue OpenC3::AuthError, OpenC3::ForbiddenError
        reject_unauthorized_connection()
      end
      true
    end
  end
end
