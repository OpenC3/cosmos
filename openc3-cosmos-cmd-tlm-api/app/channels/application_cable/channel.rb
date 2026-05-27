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
  class Channel < ActionCable::Channel::Base
    include OpenC3::Authorization

    before_subscribe :authenticate_subscription!

    private

    # Authenticate the subscription using either:
    #   1. Connection-level URL auth (legacy `?authorization=<token>` path), or
    #   2. A token supplied on the channel subscription params (preferred —
    #      keeps tokens out of WebSocket URLs / browser history / proxy logs).
    # If neither is present or valid, the subscription is rejected before
    # `subscribed` runs.
    def authenticate_subscription!
      return if connection_url_authenticated?
      token = params[:token]
      if token
        begin
          authorize(permission: 'system', scope: connection.scope, token: token)
          return
        rescue OpenC3::AuthError, OpenC3::ForbiddenError
          # fall through to reject
        end
      end
      reject
      throw :abort
    end

    # `url_authenticated` is declared as an `identified_by` on the connection
    # so AnyCable serializes it across commands (a plain ivar wouldn't survive
    # — see ApplicationCable::Connection). Stub-based channel specs that
    # don't set the identifier are treated as authenticated.
    def connection_url_authenticated?
      return true unless connection.respond_to?(:url_authenticated)
      !!connection.url_authenticated
    end
  end
end
