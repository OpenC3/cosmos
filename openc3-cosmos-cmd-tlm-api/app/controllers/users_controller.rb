
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
  require 'openc3-enterprise/controllers/users_controller'
rescue LoadError
  class UsersController < ApplicationController
    def active()
      render json: []
    end

    def logout()
      # Require a valid token so logout is not reachable unauthenticated (CWE-306)
      return unless authorization('system')
      # Terminate only the caller's own session token (from the Authorization
      # header), not the entire global sessions store, so one user logging out
      # does not log out every other operator.
      OpenC3::AuthModel.terminate(request.headers['HTTP_AUTHORIZATION'])
      head :ok
    end
  end
end
