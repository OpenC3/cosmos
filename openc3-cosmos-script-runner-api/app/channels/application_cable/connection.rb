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
    # AnyCable is stateless between commands — only `identified_by` values
    # are serialized and restored across subscribe/perform/unsubscribe calls.
    # A plain instance variable set in `connect` would be lost by the time
    # a channel's `subscribed` runs in a separate command.
    identified_by :url_authenticated

    def connect
      self.uuid = SecureRandom.uuid
      self.scope = request.query_parameters[:scope]
      # When a token is supplied on the URL, authenticate the whole connection
      # now (legacy path). Otherwise allow the connection and require each
      # subscribing channel to authenticate via its own params — that keeps
      # tokens out of WebSocket URLs (and therefore out of browser history /
      # proxy logs).
      #
      # The URL token path is deprecated and will be removed in COSMOS 8. It
      # only remains for clients older than COSMOS 7.2.0. Their token appears in
      # proxy access logs (including Traefik's) because it's part of the URL.
      if request.query_parameters[:authorization]
        authorization('script_view')
        # Only reached once authorized (a rejection raises). Never include the
        # token itself in this message.
        OpenC3::Logger.warn("A client authenticated its WebSocket with a token in the URL (deprecated, removed in COSMOS 8). Upgrade the client to COSMOS 7.2.0 or later.", scope: request.query_parameters[:scope])
        self.url_authenticated = true
      else
        self.url_authenticated = false
      end
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
