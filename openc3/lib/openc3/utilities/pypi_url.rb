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

require 'uri'
require 'openc3/utilities/logger'

module OpenC3
  class PypiUrl
    DEFAULT = 'https://pypi.org/simple'

    # Validate that a resolved pypi_url is an http(s) URL before it is handed to
    # pip. The value can come from a user-writable setting or ENV, so a malformed
    # or non-http value is rejected and replaced with the default rather than
    # passed through to pip.
    #
    # @param pypi_url [String] the resolved pypi index url to validate
    # @return [String] the original url if valid, otherwise DEFAULT
    def self.validate(pypi_url)
      uri = URI.parse(pypi_url)
      unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
        raise URI::InvalidURIError, "not an http(s) URL"
      end
      pypi_url
    rescue URI::InvalidURIError => e
      Logger.error("Invalid pypi_url '#{pypi_url}' (#{e.message}); falling back to #{DEFAULT}")
      DEFAULT
    end
  end
end
