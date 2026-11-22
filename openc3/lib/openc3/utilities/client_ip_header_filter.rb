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

module OpenC3
  # Rack middleware that removes the Client-IP and Forwarded request headers
  # before Rails computes request.remote_ip.
  #
  # COSMOS runs behind traefik, which sets X-Forwarded-For (and X-Real-Ip) from
  # the real connection. Traefik does not touch Client-IP or Forwarded, so they
  # arrive exactly as the browser sent them, yet ActionDispatch::RemoteIp uses
  # both when picking the client address. Removing them means remote_ip only
  # comes from REMOTE_ADDR and X-Forwarded-For, which traefik controls.
  #
  # Insert before ActionDispatch::RemoteIp:
  #   config.middleware.insert_before(ActionDispatch::RemoteIp, OpenC3::ClientIpHeaderFilter)
  class ClientIpHeaderFilter
    HEADERS = %w[HTTP_CLIENT_IP HTTP_FORWARDED].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      HEADERS.each { |header| env.delete(header) }
      @app.call(env)
    end
  end
end
